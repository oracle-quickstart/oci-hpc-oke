package test

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
)

type imageCache struct {
	Metadata metav1.ObjectMeta `json:"metadata"`
	Spec     struct {
		CacheSpec []struct {
			Images       []string          `json:"images"`
			NodeSelector map[string]string `json:"nodeSelector"`
		} `json:"cacheSpec"`
	} `json:"spec"`
	Status struct {
		Status         string                     `json:"status"`
		Reason         string                     `json:"reason"`
		Failures       map[string]json.RawMessage `json:"failures"`
		StartTime      *metav1.Time               `json:"startTime"`
		CompletionTime *metav1.Time               `json:"completionTime"`
	} `json:"status"`
}

// TestImageCaching provisions and tears down a cluster like the other optional suites.
func TestImageCaching(t *testing.T) {
	skipUnlessEnv(t, "RUN_IMAGE_CACHE_TESTS")
	options := newTerraformOptions(t, map[string]interface{}{
		"install_kube_fledged": true,
	})
	defer terraform.Destroy(t, options)
	terraform.InitAndApply(t, options)

	resources := terraformStateList(t, options)
	operator := false
	for _, resource := range resources {
		if strings.HasPrefix(resource, "module.kube_fledged[") {
			operator = true
		}
	}
	if operator {
		requireStateHasPrefix(t, resources, "module.kube_fledged[")
		requireStateHasPrefix(t, resources, "module.imagecaches[")
	} else {
		requireStateHasPrefix(t, resources, "helm_release.kube_fledged[")
		requireStateHasPrefix(t, resources, "helm_release.imagecaches[")
	}
	if optionalOutput(t, options, "cluster_public_endpoint") == "" {
		t.Log("Skipping Kubernetes image cache checks: no public endpoint")
		return
	}
	kubeconfigPath := generateKubeconfig(t, terraform.Output(t, options, "cluster_id"), os.Getenv("OCI_REGION"))
	runImageCacheHealthChecks(t, kubeconfigPath)
}

// TestImageCacheHealth checks a cluster already provisioned by the CI apply workflows.
func TestImageCacheHealth(t *testing.T) {
	skipUnlessEnv(t, "RUN_IMAGE_CACHE_HEALTH_CHECKS")
	runImageCacheHealthChecks(t, "")
}

func runImageCacheHealthChecks(t *testing.T, kubeconfigPath string) {
	t.Helper()
	opts := k8s.NewKubectlOptions("", kubeconfigPath, "kube-fledged")
	for _, deployment := range []string{"kube-fledged-controller", "kube-fledged-webhook-server"} {
		k8s.RunKubectl(t, opts, "rollout", "status", "deployment/"+deployment, "--timeout=120s")
	}

	// Helm's stored manifest distinguishes intentionally empty releases from missing caches.
	secretOpts := *opts
	secretOpts.Logger = logger.Discard
	output, err := k8s.RunKubectlAndGetOutputE(t, &secretOpts, "get", "secrets",
		"-l", "owner=helm,name=oci-hpc-imagecaches,status=deployed", "-o", "json", "--request-timeout=20s")
	require.NoError(t, err)
	var releases corev1.SecretList
	require.NoError(t, json.Unmarshal([]byte(output), &releases))
	require.Len(t, releases.Items, 1, "expected one deployed oci-hpc-imagecaches Helm release")
	expected, err := imageCacheNamesFromRelease(releases.Items[0].Data["release"])
	require.NoError(t, err)
	result := retry.DoWithRetry(t, "wait for image caches to populate", 270, 10*time.Second, func() (string, error) {
		output, err := k8s.RunKubectlAndGetOutputE(t, opts, "get", "imagecaches.kubefledged.io",
			"-l", "app.kubernetes.io/name=oci-hpc-imagecaches,app.kubernetes.io/instance=oci-hpc-imagecaches", "-o", "json", "--request-timeout=20s")
		if err != nil {
			return "", err
		}
		var caches struct {
			Items []imageCache `json:"items"`
		}
		if err := json.Unmarshal([]byte(output), &caches); err != nil {
			return "", err
		}
		output, err = k8s.RunKubectlAndGetOutputE(t, opts, "get", "nodes", "-o", "json", "--request-timeout=20s")
		if err != nil {
			return "", err
		}
		var nodes corev1.NodeList
		if err := json.Unmarshal([]byte(output), &nodes); err != nil {
			return "", err
		}
		if err := imageCachesProblems(caches.Items, nodes.Items, expected); err != nil {
			return "", err
		}
		return fmt.Sprintf("Validated %d ImageCache(s)", len(caches.Items)), nil
	})
	t.Log(result)
}

// Helm stores release JSON as gzip data wrapped in base64 inside its Secret.
func imageCacheNamesFromRelease(encoded []byte) (map[string]bool, error) {
	compressed, err := base64.StdEncoding.DecodeString(string(encoded))
	if err != nil {
		return nil, err
	}
	reader, err := gzip.NewReader(bytes.NewReader(compressed))
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	var release struct {
		Manifest string `json:"manifest"`
	}
	if err := json.NewDecoder(reader).Decode(&release); err != nil {
		return nil, err
	}
	expected := map[string]bool{}
	decoder := yaml.NewYAMLOrJSONDecoder(strings.NewReader(release.Manifest), 4096)
	for {
		var resource struct {
			Kind     string            `json:"kind"`
			Metadata metav1.ObjectMeta `json:"metadata"`
		}
		if err := decoder.Decode(&resource); err == io.EOF {
			return expected, nil
		} else if err != nil {
			return nil, err
		}
		if resource.Kind == "ImageCache" {
			expected[resource.Metadata.Name] = true
		}
	}
}

func imageCachesProblems(caches []imageCache, nodes []corev1.Node, expected map[string]bool) error {
	found := map[string]bool{}
	for _, cache := range caches {
		found[cache.Metadata.Name] = true
		if !expected[cache.Metadata.Name] {
			return retry.FatalError{Underlying: fmt.Errorf("unexpected cache: %s", cache.Metadata.Name)}
		}
	}
	for name := range expected {
		if !found[name] {
			return retry.FatalError{Underlying: fmt.Errorf("missing cache: %s", name)}
		}
	}
	var problems []string
	for _, cache := range caches {
		for _, problem := range imageCacheProblems(cache, nodes) {
			problems = append(problems, cache.Metadata.Name+": "+problem)
		}
	}
	if len(problems) > 0 {
		return fmt.Errorf("%s", strings.Join(problems, "; "))
	}
	return nil
}

func imageCacheProblems(cache imageCache, nodes []corev1.Node) []string {
	var problems []string
	if cache.Metadata.DeletionTimestamp != nil {
		problems = append(problems, "cache is being deleted")
	}
	for _, annotation := range []string{"kubefledged.io/refresh-imagecache", "kubefledged.io/purge-imagecache"} {
		if _, exists := cache.Metadata.Annotations[annotation]; exists {
			problems = append(problems, "refresh or purge is pending")
		}
	}
	if cache.Status.Status != "Succeeded" {
		problems = append(problems, "operation is "+cache.Status.Status)
	}
	switch cache.Status.Reason {
	case "ImageCacheCreate", "ImageCacheUpdate", "ImageCacheRefresh":
	default:
		problems = append(problems, "latest operation is not a cache population operation")
	}
	if len(cache.Status.Failures) > 0 {
		problems = append(problems, fmt.Sprintf("reported failures: %s", cache.Status.Failures))
	}
	start, end := cache.Status.StartTime, cache.Status.CompletionTime
	if start == nil || end == nil || end.Before(start) {
		problems = append(problems, "operation has no valid start/completion times")
	}
	if len(cache.Spec.CacheSpec) == 0 {
		problems = append(problems, "cacheSpec is empty")
	}
	for i, spec := range cache.Spec.CacheSpec {
		if len(spec.NodeSelector) == 0 || len(spec.Images) == 0 {
			problems = append(problems, fmt.Sprintf("cacheSpec[%d] needs images and a node selector", i))
			continue
		}
		ready := 0
		for _, node := range nodes {
			matches := true
			for key, value := range spec.NodeSelector {
				actual, exists := node.Labels[key]
				if !exists || actual != value {
					matches = false
				}
			}
			if !matches || node.DeletionTimestamp != nil {
				continue
			}
			for _, condition := range node.Status.Conditions {
				if condition.Type == corev1.NodeReady && condition.Status == corev1.ConditionTrue {
					ready++
					if start != nil && node.CreationTimestamp.After(start.Time) {
						problems = append(problems, "operation predates node "+node.Name+"; refresh required")
					}
				}
			}
		}
		if ready == 0 {
			problems = append(problems, fmt.Sprintf("cacheSpec[%d] has no matching Ready nodes", i))
		}
	}
	return problems
}

func TestImageCacheValidation(t *testing.T) {
	newCache := func() imageCache {
		var cache imageCache
		require.NoError(t, json.Unmarshal([]byte(`{
			"metadata":{"name":"oci-hpc-imagecaches-nvidia"},
			"spec":{"cacheSpec":[{"images":["test:v1"],"nodeSelector":{"nvidia.com/gpu":"true"}}]},
			"status":{"status":"Succeeded","reason":"ImageCacheRefresh",
			"startTime":"2026-11-17T10:00:00Z","completionTime":"2026-11-17T10:05:00Z"}
		}`), &cache))
		return cache
	}
	node := corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "gpu-1", Labels: map[string]string{"nvidia.com/gpu": "true"},
			CreationTimestamp: metav1.NewTime(time.Date(2026, 11, 17, 9, 0, 0, 0, time.UTC))},
		Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}},
	}
	t.Run("populated cache", func(t *testing.T) {
		require.Empty(t, imageCacheProblems(newCache(), []corev1.Node{node}))
	})
	for _, status := range []string{"Processing", "Failed", "Aborted", "NoImagesPulledOrDeleted", ""} {
		t.Run(status, func(t *testing.T) {
			cache := newCache()
			cache.Status.Status = status
			require.NotEmpty(t, imageCacheProblems(cache, []corev1.Node{node}))
		})
	}
	for name, change := range map[string]func(*imageCache){
		"purged": func(c *imageCache) { c.Status.Reason = "ImageCachePurge" },
		"failed pull": func(c *imageCache) {
			c.Status.Failures = map[string]json.RawMessage{"test:v1": json.RawMessage(`[{"reason":"ErrImagePull"}]`)}
		},
		"pending refresh": func(c *imageCache) {
			c.Metadata.Annotations = map[string]string{"kubefledged.io/refresh-imagecache": ""}
		},
		"missing completion": func(c *imageCache) { c.Status.CompletionTime = nil },
		"missing start":      func(c *imageCache) { c.Status.StartTime = nil },
		"invalid completion": func(c *imageCache) { c.Status.CompletionTime = &node.CreationTimestamp },
		"empty selector":     func(c *imageCache) { c.Spec.CacheSpec[0].NodeSelector = nil },
		"unmatched selector": func(c *imageCache) { c.Spec.CacheSpec[0].NodeSelector = map[string]string{"amd.com/gpu": "true"} },
	} {
		t.Run(name, func(t *testing.T) {
			cache := newCache()
			change(&cache)
			require.NotEmpty(t, imageCacheProblems(cache, []corev1.Node{node}))
		})
	}
	t.Run("no Ready nodes", func(t *testing.T) {
		require.NotEmpty(t, imageCacheProblems(newCache(), nil))
		notReady := node.DeepCopy()
		notReady.Status.Conditions[0].Status = corev1.ConditionFalse
		require.NotEmpty(t, imageCacheProblems(newCache(), []corev1.Node{*notReady}))
	})
	t.Run("empty label value still requires the label", func(t *testing.T) {
		cache := newCache()
		cache.Spec.CacheSpec[0].NodeSelector = map[string]string{"cache-target": ""}
		require.NotEmpty(t, imageCacheProblems(cache, []corev1.Node{node}))
		matching := node.DeepCopy()
		matching.Labels["cache-target"] = ""
		require.Empty(t, imageCacheProblems(cache, []corev1.Node{*matching}))
	})
	t.Run("new node needs refresh", func(t *testing.T) {
		newNode := node.DeepCopy()
		newNode.CreationTimestamp = metav1.NewTime(node.CreationTimestamp.Add(2 * time.Hour))
		cache := newCache()
		require.NotEmpty(t, imageCacheProblems(cache, []corev1.Node{*newNode}))
		cache.Status.StartTime = &newNode.CreationTimestamp
		cache.Status.CompletionTime = &newNode.CreationTimestamp
		require.Empty(t, imageCacheProblems(cache, []corev1.Node{*newNode}))
	})
	t.Run("missing cache", func(t *testing.T) {
		expected := map[string]bool{"oci-hpc-imagecaches-nvidia": true}
		require.NoError(t, imageCachesProblems([]imageCache{newCache()}, []corev1.Node{node}, expected))
		attempts := 0
		_, err := retry.DoWithRetryE(t, "missing cache must fail immediately", 3, 0, func() (string, error) {
			attempts++
			return "", imageCachesProblems(nil, []corev1.Node{node}, expected)
		})
		var fatal retry.FatalError
		require.ErrorAs(t, err, &fatal)
		require.ErrorContains(t, err, "missing cache: oci-hpc-imagecaches-nvidia")
		require.Equal(t, 1, attempts)
		expected["oci-hpc-imagecaches-amd"] = true
		require.ErrorContains(t, imageCachesProblems([]imageCache{newCache()}, []corev1.Node{node}, expected), "missing cache: oci-hpc-imagecaches-amd")
	})
	t.Run("intentionally empty release", func(t *testing.T) {
		require.NoError(t, imageCachesProblems(nil, nil, map[string]bool{}))
		var fatal retry.FatalError
		require.ErrorAs(t, imageCachesProblems([]imageCache{newCache()}, nil, map[string]bool{}), &fatal)
	})
	t.Run("incomplete caches remain retryable", func(t *testing.T) {
		cache := newCache()
		cache.Status.Status = "Processing"
		err := imageCachesProblems([]imageCache{cache}, []corev1.Node{node}, map[string]bool{cache.Metadata.Name: true})
		require.Error(t, err)
		var fatal retry.FatalError
		require.NotErrorAs(t, err, &fatal)
	})
	t.Run("expected caches from Helm manifest", func(t *testing.T) {
		for _, manifest := range []string{"", `apiVersion: v1
kind: ConfigMap
metadata:
  name: unrelated
---
apiVersion: kubefledged.io/v1alpha2
kind: ImageCache
metadata:
  name: oci-hpc-imagecaches-nvidia
---
apiVersion: kubefledged.io/v1alpha2
kind: ImageCache
metadata:
  name: oci-hpc-imagecaches-amd
`} {
			data, err := json.Marshal(map[string]string{"manifest": manifest})
			require.NoError(t, err)
			var compressed bytes.Buffer
			writer := gzip.NewWriter(&compressed)
			_, err = writer.Write(data)
			require.NoError(t, err)
			require.NoError(t, writer.Close())
			names, err := imageCacheNamesFromRelease([]byte(base64.StdEncoding.EncodeToString(compressed.Bytes())))
			require.NoError(t, err)
			if manifest == "" {
				require.Empty(t, names)
			} else {
				require.Equal(t, map[string]bool{"oci-hpc-imagecaches-nvidia": true, "oci-hpc-imagecaches-amd": true}, names)
			}
		}
	})
}
