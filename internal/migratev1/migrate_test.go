package migratev1

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseGeneratedConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	content := "S3_BUCKET=my\\ bucket\nBACKUP_DIRS=(\n  /srv/www\n  /etc/nginx\n)\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	doc, err := Parse(path)
	if err != nil {
		t.Fatal(err)
	}
	if doc.Scalars["S3_BUCKET"] != "my bucket" || len(doc.Arrays["BACKUP_DIRS"]) != 2 {
		t.Fatalf("unexpected parse result: %#v", doc)
	}
}

func TestParseTaskKeysWithLowercaseIDs(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tasks")
	content := "TASK_IDS=(\n  task_alpha\n)\nTASK_NAME_task_alpha=Daily\\ Site\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	doc, err := Parse(path)
	if err != nil {
		t.Fatal(err)
	}
	if doc.Scalars["TASK_NAME_task_alpha"] != "Daily Site" {
		t.Fatalf("lowercase task id was not parsed: %#v", doc)
	}
}

func TestParseRejectsCommandSubstitution(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config")
	if err := os.WriteFile(path, []byte("S3_BUCKET=$(touch /tmp/pwned)\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Parse(path); err == nil {
		t.Fatal("command substitution was accepted")
	}
}

func TestParseRejectsUnknownKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config")
	if err := os.WriteFile(path, []byte("EVIL_VALUE=hello\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Parse(path); err == nil {
		t.Fatal("unknown key was accepted")
	}
}
