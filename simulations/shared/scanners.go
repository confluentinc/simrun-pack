package shared

import (
	"context"
	"time"

	"github.com/IBM/simrun/pack"
	"github.com/sirupsen/logrus"
)

// RunCredentialScanners executes TruffleHog and Kingfisher against a credentials directory.
func RunCredentialScanners(ctx context.Context, log *logrus.Entry, sshClient *pack.SSHClient, credsDir string) {
	log.Info("Running TruffleHog")
	_, _, err := sshClient.Run(ctx, "trufflehog filesystem "+credsDir+" --results=verified --no-update")
	if err != nil {
		log.WithError(err).Warn("TruffleHog scan failed")
	}

	log.Info("Running Kingfisher")
	_, exitCode, err := sshClient.Run(ctx, "kingfisher scan "+credsDir+" --no-update-check --only-valid")
	if err != nil {
		switch exitCode {
		case 200:
			log.Info("Kingfisher: findings discovered")
		case 205:
			log.Info("Kingfisher: validated findings discovered")
		default:
			log.WithError(err).Warn("Kingfisher scan failed")
		}
	} else {
		log.Info("Kingfisher: no findings")
	}
}

// RunSSHCommands executes a list of commands via SSH with a delay between each.
func RunSSHCommands(ctx context.Context, log *logrus.Entry, sshClient *pack.SSHClient, commands []string) error {
	for _, cmd := range commands {
		_, _, err := sshClient.Run(ctx, cmd)
		if err != nil {
			log.Warn("Command may have failed")
		}
		if err := pack.Wait(ctx, time.Second); err != nil {
			return err
		}
	}
	return nil
}
