package shared

import (
	"context"
	"strings"
	"time"

	"github.com/IBM/simrun/pack"
	packaws "github.com/IBM/simrun/pack/aws"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/sirupsen/logrus"
)

// RunSSMCommands executes a list of commands via SSM with a delay between each.
// Errors on individual commands are logged but do not stop execution.
func RunSSMCommands(ctx context.Context, log *logrus.Entry, ssmClient *ssm.Client, instanceID string, commands []string, timeout, delay time.Duration) error {
	for _, cmd := range commands {
		_, err := packaws.RunSSMCommand(ctx, ssmClient, instanceID, cmd, timeout)
		if err != nil {
			log.Warn("Command may have failed")
		}
		if err := pack.Wait(ctx, delay); err != nil {
			return err
		}
	}
	return nil
}

// InstallPackagesSSM tries to install packages using yum, falling back to apt.
func InstallPackagesSSM(ctx context.Context, ssmClient *ssm.Client, instanceID string, packages []string) {
	pkgList := strings.Join(packages, " ")
	installCommands := []string{
		"yum update -y && yum install -y " + pkgList,
		"apt-get update && apt-get install -y " + pkgList,
	}
	for _, cmd := range installCommands {
		_, err := packaws.RunSSMCommand(ctx, ssmClient, instanceID, cmd, 120*time.Second)
		if err == nil {
			break
		}
	}
}
