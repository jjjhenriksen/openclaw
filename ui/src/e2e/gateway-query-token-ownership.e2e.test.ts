import { expect, it } from "vitest";
import { installMockGateway } from "../test-helpers/control-ui-e2e.ts";
import { createControlUiE2eSuite } from "./control-ui-e2e-suite.test-support.ts";

const suite = createControlUiE2eSuite({ name: "Gateway query token ownership E2E" });

suite.define(() => {
  it("keeps a migrated query token on its owning browser connection", async () => {
    await suite.withPage({ serviceWorkers: "block" }, async ({ page }) => {
      const gatewayOrigin = suite.server.baseUrl.replace(/^http/, "ws").replace(/\/$/, "");
      const owner = `${gatewayOrigin}?account=personal`;
      const neighbor = `${gatewayOrigin}?account=team`;
      const settingsPrefix = "openclaw.control.settings.v1:";
      const selectionKey = `openclaw.control.currentGateway.v1:${gatewayOrigin}`;
      const tokenPrefix = "openclaw.control.token.v1:";
      await page.addInitScript(
        ({
          ownerUrl,
          originUrl,
          ownerSelectionKey,
          persistedSettingsPrefix,
          sessionTokenPrefix,
        }) => {
          if (localStorage.getItem("openclaw.query-token-proof.ready")) return;
          localStorage.setItem("openclaw.query-token-proof.ready", "1");
          localStorage.setItem(ownerSelectionKey, ownerUrl);
          localStorage.setItem(
            `${persistedSettingsPrefix}${originUrl}`,
            JSON.stringify({
              gatewayUrl: ownerUrl,
              sessionKey: "main",
              lastActiveSessionKey: "main",
              token: "durable-owner-token",
            }),
          );
          sessionStorage.setItem(`${sessionTokenPrefix}${originUrl}`, "owner-token");
        },
        {
          ownerUrl: owner,
          originUrl: gatewayOrigin,
          ownerSelectionKey: selectionKey,
          persistedSettingsPrefix: settingsPrefix,
          sessionTokenPrefix: tokenPrefix,
        },
      );
      const gateway = await installMockGateway(page);
      await page.goto(`${suite.server.baseUrl}chat`);
      const ownerConnect = await gateway.waitForRequest("connect");
      expect(ownerConnect.params).toMatchObject({ auth: { token: "owner-token" } });

      await page.evaluate(
        ({ key, value, prefix }) => {
          localStorage.setItem(key, value);
          localStorage.setItem(
            `${prefix}${value}`,
            JSON.stringify({ gatewayUrl: value, sessionKey: "main", lastActiveSessionKey: "main" }),
          );
        },
        { key: selectionKey, value: neighbor, prefix: settingsPrefix },
      );
      await page.reload();
      const neighborConnect = await gateway.waitForRequest("connect");
      expect(neighborConnect.params).not.toMatchObject({ auth: { token: "owner-token" } });

      await page.evaluate(
        ({ key, value, tokenKey }) => {
          localStorage.setItem(key, value);
          sessionStorage.removeItem(tokenKey);
        },
        { key: selectionKey, value: owner, tokenKey: `${tokenPrefix}${owner}` },
      );
      await page.reload();
      const clearedOwnerConnect = await gateway.waitForRequest("connect");
      expect(clearedOwnerConnect.params).not.toMatchObject({ auth: { token: "owner-token" } });
      expect(
        await page.evaluate(
          (key) => JSON.parse(localStorage.getItem(key) ?? "{}"),
          `${settingsPrefix}${gatewayOrigin}`,
        ),
      ).not.toHaveProperty("token");
    });
  });
});
