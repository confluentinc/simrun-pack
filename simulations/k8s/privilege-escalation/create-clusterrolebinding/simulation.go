package simulations

import (
	"context"
	_ "embed"

	"github.com/IBM/simrun/pack"
)

//go:embed main.tf
var terraform string

func init() {
	pack.Register(pack.Simulation{
		ID:                        "create-clusterrolebinding",
		Name:                      "Create ClusterRoleBinding",
		Description:               "Creates a Kubernetes ClusterRoleBinding granting cluster-admin privileges to a simulated attacker user, simulating a privilege escalation attack via RBAC manipulation.",
		MITRE:                     pack.MITREMapping{Tactics: []string{"TA0004"}, Techniques: []string{"T1078"}},
		Scope:                     "k8s",
		RequiresExternalResources: true,
		Terraform:                 terraform,
		Detonate:                  Detonate,
	})
}

func Detonate(ctx context.Context, input pack.DetonateInput) (*pack.Result, error) {
	log := pack.Logger(input)

	bindingName := input.TerraformOutputs["binding_name"]
	clusterRole := input.TerraformOutputs["cluster_role"]
	subjectName := input.TerraformOutputs["subject_name"]

	log.WithField("binding_name", bindingName).
		WithField("cluster_role", clusterRole).
		WithField("subject", subjectName).
		Info("ClusterRoleBinding created successfully")

	return pack.SuccessResult(map[string]any{
		"binding_name": bindingName,
		"cluster_role": clusterRole,
		"subject_name": subjectName,
	}), nil
}
