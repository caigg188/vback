package config

import (
	"os"
	"testing"
)

func TestLoadRejectsUnsafeDataAndRemoteListen(t *testing.T) {
	t.Setenv("VBACK_DATA_DIR", "/")
	if _, err := Load(); err == nil {
		t.Fatal("filesystem root was accepted as data directory")
	}

	t.Setenv("VBACK_DATA_DIR", t.TempDir())
	t.Setenv("VBACK_LISTEN", "0.0.0.0:9898")
	t.Setenv("VBACK_ALLOW_REMOTE", "")
	if _, err := Load(); err == nil {
		t.Fatal("remote listen was accepted without opt-in")
	}

	t.Setenv("VBACK_ALLOW_REMOTE", "true")
	t.Setenv("VBACK_INSECURE_HTTP", "")
	if _, err := Load(); err == nil {
		t.Fatal("remote listen was accepted without TLS")
	}
}

func TestLoadRejectsHomeDirectory(t *testing.T) {
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip(err)
	}
	t.Setenv("VBACK_DATA_DIR", home)
	if _, err := Load(); err == nil {
		t.Fatal("home directory was accepted as data directory")
	}
}
