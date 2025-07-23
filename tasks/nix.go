package tasks

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/hibiken/asynq"
)

const (
	TypeNixBuild = "nix:build"
)

type NixBuildPayload struct {
	FlakeDir string
	FlakeOut string
}

type NixBuildResult struct {
	Name   string `json:"name"`
	ID     string `json:"id"`
	TS     string `json:"ts"`
	Failed bool   `json:"failed"`
}

func NewNixBuildTask(flakeDir, flakeOut string) (*asynq.Task, error) {
	payload, err := json.Marshal(&NixBuildPayload{
		FlakeDir: flakeDir,
		FlakeOut: flakeOut,
	})
	if err != nil {
		return nil, err
	}
	return asynq.NewTask(TypeNixBuild, payload), nil
}

func HandleNixBuildTask(ctx context.Context, task *asynq.Task) error {
	id, _ := asynq.GetTaskID(ctx)

	var payload NixBuildPayload
	if err := json.Unmarshal(task.Payload(), &payload); err != nil {
		return err
	}

	ts := getTS()
	resultDir := filepath.Join("/var/tmp/sylva-ci/logs/", ts)
	if err := os.MkdirAll(resultDir, 0755); err != nil {
		return err
	}

	buildErr := nixBuild(
		ctx,
		payload.FlakeDir,
		payload.FlakeOut,
		filepath.Join(resultDir, "output.log"),
	)

	result := NixBuildResult{
		Name:   payload.FlakeOut,
		ID:     id,
		TS:     ts,
		Failed: buildErr != nil,
	}
	resultJson, err := json.Marshal(result)
	if err != nil {
		return err
	}
	resultFile, err := os.Create(
		filepath.Join(resultDir, "result.json"),
	)
	if err != nil {
		return err
	}
	defer resultFile.Close()
	if _, err := resultFile.WriteString(string(resultJson) + "\n"); err != nil {
		return err
	}

	if _, err := task.ResultWriter().Write([]byte(ts)); err != nil {
		return err
	}
	return buildErr
}
