package test

import (
	"encoding/base64"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func runSlurmAddUserHelper(t *testing.T, helper string, args ...string) (string, error) {
	t.Helper()

	script, err := filepath.Abs(filepath.Join("..", "docs", "files", "slurm-add-user.sh"))
	require.NoError(t, err)
	commandArgs := []string{"-c", `source "$1"; shift; "$@"`, "bash", script, helper}
	commandArgs = append(commandArgs, args...)
	output, runErr := exec.Command("bash", commandArgs...).CombinedOutput()
	return string(output), runErr
}

func TestSlurmAddUserValidatesAccountNames(t *testing.T) {
	for _, account := range []string{"users", "project_1", "gpu-team"} {
		_, err := runSlurmAddUserHelper(t, "validate_account", account)
		require.NoError(t, err, "expected account %q to be valid", account)
	}

	for _, account := range []string{"", "Project", "bad account", "bad,account", "bad+account", "bad\nmemberUid: root"} {
		_, err := runSlurmAddUserHelper(t, "validate_account", account)
		require.Error(t, err, "expected account %q to be rejected", account)
	}
}

func TestSlurmAddUserValidatesAndEncodesFullNames(t *testing.T) {
	for _, fullName := range []string{"Alice Example", "Renée O'Connor", " #1: Cluster Admin"} {
		_, err := runSlurmAddUserHelper(t, "validate_full_name", fullName)
		require.NoError(t, err, "expected full name %q to be valid", fullName)
	}

	for _, fullName := range []string{"", "   ", "Alice\nmemberUid: root", "Alice\tAdmin", strings.Repeat("a", 257)} {
		_, err := runSlurmAddUserHelper(t, "validate_full_name", fullName)
		require.Error(t, err, "expected full name %q to be rejected", fullName)
	}

	value := " #1: Renée O'Connor, Admin"
	encoded, err := runSlurmAddUserHelper(t, "ldif_base64", value)
	require.NoError(t, err)
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	require.NoError(t, err)
	require.Equal(t, value, string(decoded))
}

func TestSlurmAddUserSerializesIdentifierAllocation(t *testing.T) {
	script := readRepositoryFile(t, "docs", "files", "slurm-add-user.sh")
	require.Contains(t, script, "kind: Lease")
	require.Contains(t, script, `kc -n "$IDENTITY_NAMESPACE" create -f -`)
	require.Contains(t, script, `trap cleanup_resources EXIT`)

	mainIndex := strings.Index(script, "\nmain() {")
	require.NotEqual(t, -1, mainIndex)
	mainBody := script[mainIndex:]
	lockIndex := strings.Index(mainBody, "acquire_allocation_lock")
	allocateIndex := strings.Index(mainBody, `allocate_ids "$USERNAME"`)
	createIndex := strings.Index(mainBody, `create_ldap_user "$USERNAME"`)
	releaseIndex := strings.Index(mainBody, "release_allocation_lock")
	require.True(t, lockIndex < allocateIndex && allocateIndex < createIndex && createIndex < releaseIndex)

	require.Contains(t, script, `cn:: ${full_name_b64}`)
	require.Contains(t, script, `sn:: ${surname_b64}`)
	require.NotContains(t, script, `cn: ${FULL_NAME}`)
	require.NotContains(t, script, `sn: ${FULL_NAME##* }`)
}

func TestSlurmAddUserLeaseTimestampUsesMicroTimeFormat(t *testing.T) {
	timestamp, err := runSlurmAddUserHelper(t, "lease_timestamp")
	require.NoError(t, err)
	require.Regexp(t,
		regexp.MustCompile(`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$`),
		strings.TrimSpace(timestamp),
	)
}
