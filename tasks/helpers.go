package tasks

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

const nixBuildScript = `
exec 2>&1
set -xe
TZ=CET date
cd '%[1]s'
nix build --option sandbox false --print-build-logs '%[2]s' --rebuild || \
nix build --option sandbox false --print-build-logs '%[2]s'
`

func nixBuild(ctx context.Context, flakeDir, flakeOut, logPath string) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	bin, err := exec.LookPath("bash")
	if err != nil {
		return err
	}
	cmd := exec.Command(bin, "--login", "-s")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin = bytes.NewReader([]byte(fmt.Sprintf(
		nixBuildScript,
		flakeDir,
		flakeOut,
	)))
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}

	done := make(chan error, 1)

	go func() {
		logFile, err := os.Create(logPath)
		if err != nil {
			done <- err; return
		}
		defer logFile.Close()

		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			if _, err := logFile.WriteString(line + "\n"); err != nil {
				done <- err; return
			}
			fmt.Println(line)
		}
		if scanner.Err() != nil {
			cmd.Process.Kill()
			cmd.Wait()
			done <- scanner.Err(); return
		}
		done <- cmd.Wait(); return
	}()

	select {
	case <-ctx.Done():
		syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		return fmt.Errorf("task terminated")
	case err := <-done:
		return err
	}
}

func getTS() string {
	tz, _ := time.LoadLocation("CET")
	now := time.Now().In(tz)
	return fmt.Sprintf(
		"%04d%02d%02d-%02d%02d%02d",
		now.Year(),
		now.Month(),
		now.Day(),
		now.Hour(),
		now.Minute(),
		now.Second(),
	)
}
