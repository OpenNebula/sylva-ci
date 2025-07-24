package main

import (
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/hibiken/asynq"
	"github.com/hibiken/asynqmon"
	"github.com/OpenNebula/sylva-ci/tasks"
)

func register(sch *asynq.Scheduler, cronSpec, flakeDir, flakeOut string) {
	task, err := tasks.NewNixBuildTask(flakeDir, flakeOut)
	if err != nil {
		log.Fatal(err)
	}
	if _, err := sch.Register(
		cronSpec,
		task,
		asynq.MaxRetry(0),
		asynq.Timeout(90 * time.Minute),
		asynq.Retention(7 * 24 * time.Hour),
	); err != nil {
		log.Fatal(err)
	}
}

func main() {
	var wg sync.WaitGroup
	wg.Add(3)

	go func() {
		defer wg.Done()
		srv := asynq.NewServer(
			asynq.RedisClientOpt{Addr: ":6379"},
			asynq.Config{Concurrency: 1},
		)
		mux := asynq.NewServeMux()
		mux.HandleFunc(tasks.TypeNixBuild, tasks.HandleNixBuildTask)
		if err := srv.Start(mux); err != nil {
			log.Fatal(err)
		}
	}()

	go func() {
		defer wg.Done()
		tz, _ := time.LoadLocation("CET")
		sch := asynq.NewScheduler(
			asynq.RedisClientOpt{Addr: ":6379"},
			&asynq.SchedulerOpts{Location: tz},
		)
		register(
			sch,
			"0 1 * * 1-5", // Mon..Fri 01:00:00
			"/opt/sylva-ci/scenario/",
			".#checks.x86_64-linux.sylva-ci-deploy-kubeadm",
		)
		register(
			sch,
			"0 1 * * 1-5", // Mon..Fri 01:00:00
			"/opt/sylva-ci/scenario/",
			".#checks.x86_64-linux.sylva-ci-deploy-rke2",
		)
		if err := sch.Start(); err != nil {
			log.Fatal(err)
		}
	}()

	go func() {
		defer wg.Done()
		if err := os.MkdirAll("/var/tmp/sylva-ci/logs/", 0755); err != nil {
			log.Fatal(err)
		}
		fs := http.FileServer(
			http.Dir("/var/tmp/sylva-ci/logs/"),
		)
		mon := asynqmon.New(asynqmon.Options{
			RootPath: "",
			RedisConnOpt: asynq.RedisClientOpt{Addr: ":6379"},
		})
		mux := http.NewServeMux()
		mux.Handle("GET /logs/", http.StripPrefix("/logs", fs))
		mux.Handle("/", mon)
		if err := http.ListenAndServe(":3000", mux); err != nil {
			log.Fatal(err)
		}
	}()

	wg.Wait()
}
