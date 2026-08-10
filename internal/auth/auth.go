package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"os"
	"runtime/debug"
	"strings"
	"time"

	"golang.org/x/crypto/argon2"

	"github.com/caigg188/vback/internal/config"
	"github.com/caigg188/vback/internal/store"
)

type contextKey string

const csrfKey contextKey = "csrf"

type Manager struct {
	cfg   config.Config
	store *store.Store
}

func New(cfg config.Config, store *store.Store) *Manager { return &Manager{cfg: cfg, store: store} }

func (m *Manager) EnsureSetupToken() (string, error) {
	if m.store.IsSetup(context.Background()) {
		_ = os.Remove(m.cfg.SetupTokenPath())
		return "", nil
	}
	if data, err := os.ReadFile(m.cfg.SetupTokenPath()); err == nil && strings.TrimSpace(string(data)) != "" {
		return strings.TrimSpace(string(data)), nil
	}
	token, err := randomToken(24)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(m.cfg.SetupTokenPath(), []byte(token+"\n"), 0o600); err != nil {
		return "", err
	}
	return token, nil
}

func (m *Manager) Setup(ctx context.Context, token, password string) error {
	if m.store.IsSetup(ctx) {
		return errors.New("already configured")
	}
	expected, err := os.ReadFile(m.cfg.SetupTokenPath())
	if err != nil {
		return errors.New("setup token unavailable")
	}
	if subtle.ConstantTimeCompare([]byte(strings.TrimSpace(string(expected))), []byte(strings.TrimSpace(token))) != 1 {
		return errors.New("invalid setup token")
	}
	if len(password) < 10 {
		return errors.New("password must be at least 10 characters")
	}
	hash, err := HashPassword(password)
	if err != nil {
		return err
	}
	if err := m.store.SetSetting(ctx, "admin_password", hash); err != nil {
		return err
	}
	return os.Remove(m.cfg.SetupTokenPath())
}

func (m *Manager) Login(ctx context.Context, password string) (token, csrf string, err error) {
	encoded, err := m.store.Setting(ctx, "admin_password")
	if err != nil {
		return "", "", errors.New("setup required")
	}
	ok, err := VerifyPassword(password, encoded)
	if err != nil || !ok {
		return "", "", errors.New("invalid credentials")
	}
	token, err = randomToken(32)
	if err != nil {
		return "", "", err
	}
	csrf, err = randomToken(24)
	if err != nil {
		return "", "", err
	}
	err = m.store.SaveSession(ctx, hashToken(token), csrf, time.Now().Add(24*time.Hour))
	return
}

func (m *Manager) Logout(ctx context.Context, token string) error {
	return m.store.DeleteSession(ctx, hashToken(token))
}

func (m *Manager) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/v1/") || isPublic(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}
		cookie, err := r.Cookie("vback_session")
		if err != nil {
			writeUnauthorized(w)
			return
		}
		csrf, err := m.store.Session(r.Context(), hashToken(cookie.Value))
		if err != nil {
			writeUnauthorized(w)
			return
		}
		if r.Method != "GET" && r.Method != "HEAD" && r.Method != "OPTIONS" {
			if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-CSRF-Token")), []byte(csrf)) != 1 {
				http.Error(w, `{"error":"invalid csrf token"}`, http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), csrfKey, csrf)))
	})
}

func CSRF(ctx context.Context) string { value, _ := ctx.Value(csrfKey).(string); return value }

func isPublic(path string) bool {
	return path == "/api/v1/health" || path == "/api/v1/setup" || path == "/api/v1/login"
}

func writeUnauthorized(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_, _ = w.Write([]byte(`{"error":"authentication required"}`))
}

func HashPassword(password string) (string, error) {
	defer debug.FreeOSMemory()
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := argon2.IDKey([]byte(password), salt, 2, 19*1024, 1, 32)
	return fmt.Sprintf("$argon2id$v=19$m=19456,t=2,p=1$%s$%s", base64.RawStdEncoding.EncodeToString(salt), base64.RawStdEncoding.EncodeToString(hash)), nil
}

func VerifyPassword(password, encoded string) (bool, error) {
	defer debug.FreeOSMemory()
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 {
		return false, errors.New("invalid password hash")
	}
	var memory uint32
	var iterations uint32
	var parallelism uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &iterations, &parallelism); err != nil {
		return false, err
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, err
	}
	expected, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, err
	}
	actual := argon2.IDKey([]byte(password), salt, iterations, memory, parallelism, uint32(len(expected)))
	return subtle.ConstantTimeCompare(actual, expected) == 1, nil
}

func randomToken(size int) (string, error) {
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}
func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
