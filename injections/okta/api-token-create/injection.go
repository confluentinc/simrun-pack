package apitokencreate

import (
	_ "embed"

	"github.com/IBM/simrun/pack"
)

//go:embed injection.tpl
var injectionTemplate string

func init() {
	pack.RegisterTemplate(pack.Template{
		ID:          "api-token-create",
		Name:        "Okta API Token Created",
		Description: "Log injection template for an Okta system.api_token.create event",
		Scope:       "okta",
		Content:     injectionTemplate,
	})
}
