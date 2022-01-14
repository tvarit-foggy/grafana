package middleware

import (
	"context"
	"fmt"
	"testing"

	"github.com/grafana/grafana/pkg/bus"
	"github.com/grafana/grafana/pkg/models"
	"github.com/stretchr/testify/assert"
)

func TestViewRedirectMiddleware(t *testing.T) {
	middlewareScenario(t, "when setting a correct view for the user", func(t *testing.T, sc *scenarioContext) {
		sc.withTokenSessionCookie("token")
		bus.AddHandler("test", func(ctx context.Context, query *models.SetViewCommand) error {
			return nil
		})

		bus.AddHandler("test", func(ctx context.Context, query *models.GetSignedInUserQuery) error {
			query.Result = &models.SignedInUser{OrgId: 1, UserId: 12, View: "Platform"}
			return nil
		})

		sc.userAuthTokenService.LookupTokenProvider = func(ctx context.Context, unhashedToken string) (*models.UserToken, error) {
			return &models.UserToken{
				UserId:        0,
				UnhashedToken: "",
			}, nil
		}

		sc.m.Get("/", sc.defaultHandler)
		sc.fakeReq("GET", "/?view=Global").exec()

		assert.Equal(t, 302, sc.resp.Code)
	})

	middlewareScenario(t, "when setting an invalid view for user", func(t *testing.T, sc *scenarioContext) {
		sc.withTokenSessionCookie("token")
		bus.AddHandler("test", func(ctx context.Context, query *models.SetViewCommand) error {
			return fmt.Errorf("")
		})

		bus.AddHandler("test", func(ctx context.Context, query *models.GetSignedInUserQuery) error {
			query.Result = &models.SignedInUser{OrgId: 1, UserId: 12, View: "Platform"}
			return nil
		})

		sc.userAuthTokenService.LookupTokenProvider = func(ctx context.Context, unhashedToken string) (*models.UserToken, error) {
			return &models.UserToken{
				UserId:        12,
				UnhashedToken: "",
			}, nil
		}

		sc.m.Get("/", sc.defaultHandler)
		sc.fakeReq("GET", "/?view=Global").exec()

		assert.Equal(t, 404, sc.resp.Code)
	})
}
