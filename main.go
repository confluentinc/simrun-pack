// Package main is the entrypoint for the simrun-base simulation pack.
package main

import (
	"github.com/IBM/simrun/pack"
	// AWS simulations
	_ "github.com/confluentinc/simrun-pack/simulations/aws/credential-access/credential-scanner-tools"
	_ "github.com/confluentinc/simrun-pack/simulations/aws/discovery/s3-list-objects"
	// Kubernetes simulations
	_ "github.com/confluentinc/simrun-pack/simulations/k8s/credential-access/eks-web-identity-token-theft"
	_ "github.com/confluentinc/simrun-pack/simulations/k8s/privilege-escalation/create-clusterrolebinding"
	// Okta injections
	_ "github.com/confluentinc/simrun-pack/injections/okta/api-token-create"
)

// Version is set via ldflags at build time.
var Version = "dev"

func main() {
	pack.SetPackInfo("simrun-base-pack", Version, "0.4.0")
	pack.RegisterPackParams(
		pack.PackParam{
			Name:        "resource_prefix",
			Type:        pack.PackParamTypeString,
			Description: "Prefix applied to every resource name the pack creates.",
			Default:     "simrun",
		},
		pack.PackParam{
			Name:        "aws_vpc_id",
			Type:        pack.PackParamTypeString,
			Description: "ID of the pre-existing AWS VPC simulations launch resources into.",
		},
		pack.PackParam{
			Name:        "aws_subnet_id",
			Type:        pack.PackParamTypeString,
			Description: "ID of the pre-existing AWS subnet simulations launch resources into.",
		},
	)
	pack.Run()
}
