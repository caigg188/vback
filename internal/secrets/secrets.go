package secrets

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/caigg188/vback/internal/domain"
)

func Write(dir, repositoryID string, secret domain.Secret) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, repositoryID+".json")
	temp, err := os.CreateTemp(dir, repositoryID+".*.tmp")
	if err != nil {
		return "", err
	}
	name := temp.Name()
	defer os.Remove(name)
	if err := temp.Chmod(0o600); err != nil {
		temp.Close()
		return "", err
	}
	encoder := json.NewEncoder(temp)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(secret); err != nil {
		temp.Close()
		return "", err
	}
	if err := temp.Sync(); err != nil {
		temp.Close()
		return "", err
	}
	if err := temp.Close(); err != nil {
		return "", err
	}
	if err := os.Rename(name, path); err != nil {
		return "", err
	}
	return path, nil
}

func Read(path string) (domain.Secret, error) {
	var secret domain.Secret
	info, err := os.Stat(path)
	if err != nil {
		return secret, err
	}
	if info.Mode().Perm()&0o077 != 0 {
		return secret, fmt.Errorf("secret file %s must not be group/world accessible", path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return secret, err
	}
	if err := json.Unmarshal(data, &secret); err != nil {
		return secret, err
	}
	if secret.ResticPassword == "" {
		return secret, fmt.Errorf("restic password is missing")
	}
	return secret, nil
}

func PasswordFile(secretPath string) (string, error) {
	secret, err := Read(secretPath)
	if err != nil {
		return "", err
	}
	file, err := os.CreateTemp(filepath.Dir(secretPath), ".restic-password-*.tmp")
	if err != nil {
		return "", err
	}
	path := file.Name()
	defer func() {
		if err != nil {
			_ = os.Remove(path)
		}
	}()
	if err = file.Chmod(0o600); err != nil {
		_ = file.Close()
		return "", err
	}
	if _, err = file.WriteString(secret.ResticPassword + "\n"); err != nil {
		_ = file.Close()
		return "", err
	}
	if err = file.Close(); err != nil {
		return "", err
	}
	return path, nil
}
