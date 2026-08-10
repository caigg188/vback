package store

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/caigg188/vback/internal/domain"
)

func TestRecoverInterruptedRuns(t *testing.T) {
	st, err := Open(filepath.Join(t.TempDir(), "vback.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	run := domain.Run{
		ID: uuid.NewString(), RepositoryID: uuid.NewString(), Kind: "backup",
		Status: "queued", StartedAt: time.Now().UTC(),
	}
	if err := st.CreateRun(context.Background(), run); err != nil {
		t.Fatal(err)
	}
	if err := st.RecoverInterruptedRuns(context.Background()); err != nil {
		t.Fatal(err)
	}
	recovered, err := st.Run(context.Background(), run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if recovered.Status != "failed" || recovered.FinishedAt == nil || recovered.Error == "" {
		t.Fatalf("interrupted run was not recovered: %#v", recovered)
	}
}
