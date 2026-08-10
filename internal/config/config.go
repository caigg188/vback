package config

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type Config struct {
	DataDir      string
	Listen       string
	TLSCert      string
	TLSKey       string
	AllowRemote  bool
	InsecureHTTP bool
	ResticPath   string
	SQLitePath   string
}

func Load() (Config, error) {
	dataDir := os.Getenv("VBACK_DATA_DIR")
	if dataDir == "" {
		if runtime.GOOS == "linux" && os.Geteuid() == 0 {
			dataDir = "/var/lib/vback"
		} else if state := os.Getenv("XDG_STATE_HOME"); state != "" {
			dataDir = filepath.Join(state, "vback")
		} else {
			home, _ := os.UserHomeDir()
			dataDir = filepath.Join(home, ".local", "state", "vback")
		}
	}
	abs, err := filepath.Abs(dataDir)
	if err != nil {
		return Config{}, err
	}
	if abs == "/" {
		return Config{}, errors.New("refusing to use filesystem root as data directory")
	}
	if home, homeErr := os.UserHomeDir(); homeErr == nil {
		homeAbs, _ := filepath.Abs(home)
		if abs == homeAbs {
			return Config{}, errors.New("refusing to use the user home directory as data directory")
		}
	}
	listen := envOr("VBACK_LISTEN", "127.0.0.1:9898")
	cfg := Config{
		DataDir:      abs,
		Listen:       listen,
		TLSCert:      os.Getenv("VBACK_TLS_CERT"),
		TLSKey:       os.Getenv("VBACK_TLS_KEY"),
		AllowRemote:  envBool("VBACK_ALLOW_REMOTE"),
		InsecureHTTP: envBool("VBACK_INSECURE_HTTP"),
		ResticPath:   envOr("VBACK_RESTIC_PATH", "restic"),
		SQLitePath:   envOr("VBACK_SQLITE_PATH", "sqlite3"),
	}
	if err := cfg.validateListen(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c Config) DBPath() string          { return filepath.Join(c.DataDir, "vback.db") }
func (c Config) SecretDir() string       { return filepath.Join(c.DataDir, "secrets") }
func (c Config) RestoreDir() string      { return filepath.Join(c.DataDir, "restores") }
func (c Config) StagingDir() string      { return filepath.Join(c.DataDir, "staging") }
func (c Config) SetupTokenPath() string  { return filepath.Join(c.DataDir, "setup-token") }
func (c Config) ServiceLockPath() string { return filepath.Join(c.DataDir, "service.lock") }

func (c Config) EnsureDirs() error {
	for _, dir := range []string{c.DataDir, c.SecretDir(), c.RestoreDir(), c.StagingDir()} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return err
		}
		if err := os.Chmod(dir, 0o700); err != nil {
			return err
		}
	}
	return nil
}

func (c Config) validateListen() error {
	host, _, err := net.SplitHostPort(c.Listen)
	if err != nil {
		return fmt.Errorf("invalid listen address: %w", err)
	}
	ip := net.ParseIP(host)
	loopback := host == "localhost" || (ip != nil && ip.IsLoopback())
	if loopback {
		return nil
	}
	if !c.AllowRemote {
		return errors.New("non-loopback listen requires VBACK_ALLOW_REMOTE=true")
	}
	if (c.TLSCert == "" || c.TLSKey == "") && !c.InsecureHTTP {
		return errors.New("remote listen requires TLS certificate/key; use a loopback reverse proxy or explicitly set VBACK_INSECURE_HTTP=true")
	}
	return nil
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func envBool(key string) bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(key))) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}
