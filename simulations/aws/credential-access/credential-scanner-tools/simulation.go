package simulations

import (
	"context"
	_ "embed"
	"fmt"
	"time"

	"github.com/IBM/simrun/pack"
	"github.com/confluentinc/simrun-pack/simulations/shared"
)

//go:embed main.tf
var terraform string

func init() {
	pack.Register(pack.Simulation{
		ID:          "credential-scanner-tools",
		Name:        "Execute Credential Scanning Tools for AWS Credentials",
		Description: "Executes TruffleHog and Kingfisher credential scanners to discover and validate AWS access keys.",
		MITRE:       pack.MITREMapping{Tactics: []string{"TA0006"}, Techniques: []string{"T1552.001"}},
		Scope:       "aws",
		IsSlow:      true,
		Terraform:   terraform,
		Detonate:    Detonate,
	})
}

func Detonate(ctx context.Context, input pack.DetonateInput) (*pack.Result, error) {
	log := pack.Logger(input)

	vmName := input.TerraformOutputs["vm_name"]
	azureRegion := input.TerraformOutputs["azure_region"]
	vmPublicIP := input.TerraformOutputs["attacker_vm_public_ip"]
	awsAccessKeyID := input.TerraformOutputs["aws_access_key_id"]
	awsSecretAccessKey := input.TerraformOutputs["aws_secret_access_key"]

	log.WithField("vm_name", vmName).WithField("azure_region", azureRegion).
		Info("Starting credential scanning simulation")

	log.Info("Waiting for Azure VM to be ready for SSH access")
	pack.Wait(ctx, 2*time.Minute)

	sshClient, err := pack.SSHClientFromTerraform(input.TerraformOutputs, log)
	if err != nil {
		return nil, fmt.Errorf("failed to create SSH client: %w", err)
	}

	// Write AWS credentials file
	log.Info("Setting up credentials on remote VM")
	setupCredsCmd := fmt.Sprintf("mkdir -p /tmp/creds && cat > /tmp/creds/aws_credentials.txt << 'AWSEOF'\naws_access_key_id = %s\naws_secret_access_key = %s\nregion = us-west-2\nAWSEOF", awsAccessKeyID, awsSecretAccessKey)
	if _, _, err = sshClient.Run(ctx, setupCredsCmd); err != nil {
		return nil, fmt.Errorf("failed to setup credentials: %w", err)
	}

	shared.RunCredentialScanners(ctx, log, sshClient, "/tmp/creds")

	log.Info("AWS credential scanning simulation completed")

	return pack.SuccessResult(map[string]any{
		"vm_name":      vmName,
		"vm_public_ip": vmPublicIP,
		"azure_region": azureRegion,
	}), nil
}
