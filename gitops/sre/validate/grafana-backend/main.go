package main

import (
	"context"
	"log"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
	"github.com/grafana/grafana-plugin-sdk-go/backend/app"
	"github.com/grafana/grafana-plugin-sdk-go/backend/instancemgmt"
)

func newInstance(
	ctx context.Context,
	settings backend.AppInstanceSettings,
) (instancemgmt.Instance, error) {

	token := settings.DecryptedSecureJSONData["controllerToken"]

	return newApp(token)
}

func main() {
	err := app.Manage(
		pluginID,
		newInstance,
		app.ManageOpts{},
	)

	if err != nil {
		log.Fatal("Capstone backend initialization failed")
	}
}
