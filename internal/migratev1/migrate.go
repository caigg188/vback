package migratev1

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/caigg188/vback/internal/config"
	"github.com/caigg188/vback/internal/domain"
	"github.com/caigg188/vback/internal/secrets"
	"github.com/caigg188/vback/internal/store"
)

type Document struct {
	Scalars map[string]string
	Arrays  map[string][]string
}

type Preview struct {
	Provider  string   `json:"provider"`
	Bucket    string   `json:"bucket"`
	Tasks     int      `json:"tasks"`
	Schedules int      `json:"schedules"`
	Warnings  []string `json:"warnings"`
}

var assignment = regexp.MustCompile(`^([A-Za-z_][A-Za-z0-9_]*)=(.*)$`)
var safeName = regexp.MustCompile(`^(CLOUD_PROVIDER|S3_ACCESS_KEY|S3_SECRET_KEY|S3_ENDPOINT|S3_BUCKET|S3_REGION|BACKUP_PREFIX|MAX_BACKUPS|COMPRESS_BACKUP|COMPRESSION_LEVEL|SQLITE_SAFE_BACKUP|SCHEDULE_CRON|ACTIVE_TASK_ID|DEFAULT_TASK_ID|TASK_IDS|SCHEDULE_IDS|TASK_(NAME|PREFIX|MAX_BACKUPS|COMPRESS|COMPRESSION_LEVEL|SQLITE_SAFE|DIRS|EXCLUDES)_[A-Za-z0-9_]+|SCHEDULE_(NAME|TASK|CRON)_[A-Za-z0-9_]+|BACKUP_DIRS|EXCLUDE_PATTERNS)$`)

func Parse(path string) (Document, error) {
	file, err := os.Open(path)
	if err != nil {
		return Document{}, err
	}
	defer file.Close()
	doc := Document{Scalars: map[string]string{}, Arrays: map[string][]string{}}
	scanner := bufio.NewScanner(file)
	var arrayName string
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if arrayName != "" {
			if line == ")" {
				arrayName = ""
				continue
			}
			value, err := decodeWord(line)
			if err != nil {
				return doc, fmt.Errorf("%s: %w", path, err)
			}
			doc.Arrays[arrayName] = append(doc.Arrays[arrayName], value)
			continue
		}
		match := assignment.FindStringSubmatch(line)
		if match == nil {
			return doc, fmt.Errorf("%s: unsupported statement", path)
		}
		name, value := match[1], strings.TrimSpace(match[2])
		if !safeName.MatchString(name) {
			return doc, fmt.Errorf("%s: unsupported key %s", path, name)
		}
		if value == "(" {
			arrayName = name
			doc.Arrays[name] = []string{}
			continue
		}
		decoded, err := decodeWord(value)
		if err != nil {
			return doc, fmt.Errorf("%s: key %s: %w", path, name, err)
		}
		doc.Scalars[name] = decoded
	}
	if err := scanner.Err(); err != nil {
		return doc, err
	}
	if arrayName != "" {
		return doc, errors.New("unterminated array")
	}
	return doc, nil
}

func LoadDir(dir string) (Document, error) {
	merged := Document{Scalars: map[string]string{}, Arrays: map[string][]string{}}
	found := false
	for _, name := range []string{"config", "tasks", "schedules"} {
		doc, err := Parse(filepath.Join(dir, name))
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return merged, err
		}
		found = true
		for k, v := range doc.Scalars {
			merged.Scalars[k] = v
		}
		for k, v := range doc.Arrays {
			merged.Arrays[k] = v
		}
	}
	if !found {
		return merged, errors.New("no v1 config files found")
	}
	return merged, nil
}

func Inspect(doc Document) Preview {
	taskIDs := doc.Arrays["TASK_IDS"]
	if len(taskIDs) == 0 && len(doc.Arrays["BACKUP_DIRS"]) > 0 {
		taskIDs = []string{"task_default"}
	}
	return Preview{Provider: doc.Scalars["CLOUD_PROVIDER"], Bucket: doc.Scalars["S3_BUCKET"], Tasks: len(taskIDs), Schedules: len(doc.Arrays["SCHEDULE_IDS"]), Warnings: []string{"Imported schedules are disabled until reviewed", "Legacy tar archives are not converted to restic snapshots"}}
}

func Import(ctx context.Context, cfg config.Config, st *store.Store, dir, resticPassword string) (Preview, error) {
	doc, err := LoadDir(dir)
	if err != nil {
		return Preview{}, err
	}
	preview := Inspect(doc)
	if preview.Bucket == "" || doc.Scalars["S3_ENDPOINT"] == "" {
		return preview, errors.New("v1 storage configuration is incomplete")
	}
	if resticPassword == "" {
		return preview, errors.New("a restic recovery password is required for confirmed import")
	}
	taskIDs := doc.Arrays["TASK_IDS"]
	if len(taskIDs) == 0 {
		taskIDs = []string{"task_default"}
	}
	schedulesByTask := map[string]string{}
	for _, scheduleID := range doc.Arrays["SCHEDULE_IDS"] {
		taskID := doc.Scalars["SCHEDULE_TASK_"+scheduleID]
		if schedulesByTask[taskID] == "" {
			schedulesByTask[taskID] = doc.Scalars["SCHEDULE_CRON_"+scheduleID]
		}
	}
	now := time.Now().UTC()
	for _, oldID := range taskIDs {
		suffix := "_" + oldID
		dirs := doc.Arrays["TASK_DIRS"+suffix]
		if len(dirs) == 0 && oldID == "task_default" {
			dirs = doc.Arrays["BACKUP_DIRS"]
		}
		if len(dirs) == 0 {
			preview.Warnings = append(preview.Warnings, "Skipped task "+oldID+": no sources")
			continue
		}
		oldPrefix := doc.Scalars["TASK_PREFIX"+suffix]
		if oldPrefix == "" && oldID == "task_default" {
			oldPrefix = doc.Scalars["BACKUP_PREFIX"]
		}
		repoID := uuid.NewString()
		secretPath, err := secrets.Write(cfg.SecretDir(), repoID, domain.Secret{AccessKey: doc.Scalars["S3_ACCESS_KEY"], SecretKey: doc.Scalars["S3_SECRET_KEY"], ResticPassword: resticPassword})
		if err != nil {
			return preview, err
		}
		prefix := strings.Trim(oldPrefix, "/")
		if prefix != "" {
			prefix += "/"
		}
		prefix += "v2"
		repo := domain.Repository{ID: repoID, Name: "Imported " + oldID, Provider: doc.Scalars["CLOUD_PROVIDER"], Endpoint: doc.Scalars["S3_ENDPOINT"], Bucket: doc.Scalars["S3_BUCKET"], Prefix: prefix, Region: doc.Scalars["S3_REGION"], SecretFile: secretPath, Health: "unknown", CreatedAt: now, UpdatedAt: now}
		if err := st.UpsertRepository(ctx, repo); err != nil {
			return preview, err
		}
		sources := make([]domain.Source, 0, len(dirs))
		for _, dir := range dirs {
			sources = append(sources, domain.Source{Path: dir, Alias: filepath.Base(dir)})
		}
		excludes := doc.Arrays["TASK_EXCLUDES"+suffix]
		if len(excludes) == 0 {
			excludes = doc.Arrays["EXCLUDE_PATTERNS"]
		}
		retention := domain.Retention{Last: parseInt(doc.Scalars["TASK_MAX_BACKUPS"+suffix], 7)}
		job := domain.Job{ID: uuid.NewString(), Name: firstNonEmpty(doc.Scalars["TASK_NAME"+suffix], oldID), RepositoryID: repoID, Sources: sources, Excludes: excludes, Schedule: schedulesByTask[oldID], Timezone: "UTC", Retention: retention, LowResource: true, Enabled: false, CreatedAt: now, UpdatedAt: now}
		if err := st.UpsertJob(ctx, job); err != nil {
			return preview, err
		}
	}
	return preview, nil
}

func decodeWord(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", nil
	}
	if strings.Contains(value, "$(") || strings.Contains(value, "`") || strings.Contains(value, "${") {
		return "", errors.New("command or parameter expansion is forbidden")
	}
	if strings.HasPrefix(value, "$'") {
		return "", errors.New("ANSI-C shell strings are not accepted")
	}
	if (strings.HasPrefix(value, "\"") && strings.HasSuffix(value, "\"")) || (strings.HasPrefix(value, "'") && strings.HasSuffix(value, "'")) {
		if value[0] == '\'' {
			return strings.Trim(value, "'"), nil
		}
		decoded, err := strconv.Unquote(value)
		if err != nil {
			return "", err
		}
		return decoded, nil
	}
	var out strings.Builder
	escaped := false
	for _, ch := range value {
		if escaped {
			out.WriteRune(ch)
			escaped = false
			continue
		}
		if ch == '\\' {
			escaped = true
			continue
		}
		if strings.ContainsRune(";|&<>", ch) {
			return "", errors.New("shell operator is forbidden")
		}
		out.WriteRune(ch)
	}
	if escaped {
		out.WriteRune('\\')
	}
	return out.String(), nil
}
func parseInt(value string, fallback int) int {
	n, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return n
}
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
