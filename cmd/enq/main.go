package main

import (
	"log"
	"time"

	"github.com/hibiken/asynq"
	"github.com/OpenNebula/sylva-ci/tasks"
)

func enqueue(client *asynq.Client, flakeDir, flakeOut string) {
	task, err := tasks.NewNixBuildTask(flakeDir, flakeOut)
	if err != nil {
		log.Fatal(err)
	}
	info, err := client.Enqueue(
		task,
		asynq.MaxRetry(0),
		asynq.Timeout(90 * time.Minute),
		asynq.Retention(7 * 24 * time.Hour),
	)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("enqueued %s: id=%s queue=%s", flakeOut, info.ID, info.Queue)
}

func main() {
	client := asynq.NewClient(asynq.RedisClientOpt{Addr: ":6379"})
	defer client.Close()
	enqueue(
		client,
		"/opt/sylva-ci/scenario/",
		".#checks.x86_64-linux.sylva-ci-deploy-kubeadm",
	)
	enqueue(
		client,
		"/opt/sylva-ci/scenario/",
		".#checks.x86_64-linux.sylva-ci-deploy-rke2",
	)
}
