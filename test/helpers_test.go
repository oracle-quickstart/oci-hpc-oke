package test

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestBaseVarsAllowsMissingSSHPublicKeyWhenVarFilesAreUsed(t *testing.T) {
	t.Setenv("TFVARS_FILE", "./tfvars/base/base.tfvars")

	vars := baseVars(t, baseVarsOptions{
		includeDefaults:      false,
		allowMissingRequired: true,
	})

	_, exists := vars["ssh_public_key"]
	require.False(t, exists)
}
