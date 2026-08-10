package scheduler

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/robfig/cron/v3"

	"github.com/caigg188/vback/internal/restic"
	"github.com/caigg188/vback/internal/store"
)

type Scheduler struct {
	store  *store.Store
	runner *restic.Runner
	mu     sync.Mutex
	engine *cron.Cron
}

func New(store *store.Store, runner *restic.Runner) *Scheduler {
	return &Scheduler{store: store, runner: runner}
}

func (s *Scheduler) Reload(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.engine != nil {
		stop := s.engine.Stop()
		select {
		case <-stop.Done():
		case <-time.After(2 * time.Second):
		}
	}
	engine := cron.New()
	jobs, err := s.store.Jobs(ctx)
	if err != nil {
		return err
	}
	for _, job := range jobs {
		if !job.Enabled || job.Schedule == "" {
			_ = s.store.UpdateJobNextRun(ctx, job.ID, nil)
			continue
		}
		spec := job.Schedule
		if job.Timezone != "" {
			spec = "CRON_TZ=" + job.Timezone + " " + spec
		}
		jobID := job.ID
		schedule, err := cron.ParseStandard(spec)
		if err != nil {
			return fmt.Errorf("job %s schedule: %w", job.Name, err)
		}
		entryID := engine.Schedule(schedule, cron.FuncJob(func() {
			_, _ = s.runner.StartBackup(context.Background(), jobID, false)
			next := schedule.Next(time.Now())
			_ = s.store.UpdateJobNextRun(context.Background(), jobID, &next)
		}))
		entry := engine.Entry(entryID)
		next := entry.Schedule.Next(time.Now())
		_ = s.store.UpdateJobNextRun(ctx, job.ID, &next)
	}
	repositories, err := s.store.Repositories(ctx)
	if err != nil {
		return err
	}
	for _, repository := range repositories {
		repositoryID := repository.ID
		_, _ = engine.AddFunc("CRON_TZ=UTC 0 4 * * 0", func() {
			_, _ = s.runner.Check(context.Background(), repositoryID)
		})
	}
	if enabled, _ := s.store.Setting(ctx, "monthly_full_check"); enabled == "true" {
		for _, repository := range repositories {
			repositoryID := repository.ID
			_, _ = engine.AddFunc("CRON_TZ=UTC 0 5 1 * *", func() {
				_, _ = s.runner.FullCheck(context.Background(), repositoryID)
			})
		}
	}
	if pruneSpec, _ := s.store.Setting(ctx, "prune_schedule"); pruneSpec != "" {
		if _, err := cron.ParseStandard(pruneSpec); err != nil {
			return fmt.Errorf("prune schedule: %w", err)
		}
		for _, repository := range repositories {
			repositoryID := repository.ID
			_, _ = engine.AddFunc(pruneSpec, func() {
				_, _ = s.runner.Maintenance(context.Background(), repositoryID, "prune")
			})
		}
	}
	engine.Start()
	s.engine = engine
	return nil
}

func (s *Scheduler) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.engine != nil {
		s.engine.Stop()
		s.engine = nil
	}
}
