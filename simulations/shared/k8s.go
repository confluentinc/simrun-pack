package shared

import (
	"fmt"
	"os"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// NewKubernetesClient creates a Kubernetes clientset and REST config from the
// KUBECONFIG environment variable. This is set by the k8s connector system
// before pack execution. The REST config is returned alongside the clientset
// for operations that need it directly (e.g. exec via remotecommand).
func NewKubernetesClient() (*kubernetes.Clientset, *rest.Config, error) {
	kubeconfigPath := os.Getenv("KUBECONFIG")
	if kubeconfigPath == "" {
		return nil, nil, fmt.Errorf("KUBECONFIG environment variable is not set")
	}

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to build kubeconfig from %s: %w", kubeconfigPath, err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	return clientset, config, nil
}
