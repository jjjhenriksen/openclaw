import fs from "node:fs";
import path from "node:path";
import { expectDefined } from "@openclaw/normalization-core/expect";
import { afterEach, expect, it, vi } from "vitest";
import { useAutoCleanupTempDirTracker } from "../../test/helpers/temp-dir.js";
import { listPluginDoctorStateMigrationEntries } from "./doctor-contract-registry.js";
import { createPluginCache, retirePluginCache, withPluginCache } from "./plugin-cache.js";
import { getPluginValueInstance } from "./plugin-instance-scope.js";
import { PluginInstance } from "./plugin-instance.js";
import { createPluginManifestRecordFixture } from "./plugin-metadata.test-support.js";
import { getPluginSetupModuleLoader } from "./plugin-setup-module.js";

const dirs = useAutoCleanupTempDirTracker(afterEach);

function fixture(basename = "doctor-contract-api") {
  const rootDir = fs.realpathSync(dirs.make("doctor-selective-capture-"));
  const source = path.join(rootDir, `${basename}.mjs`);
  const write = (name: string, body: string) => {
    const filename = path.join(rootDir, name);
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.writeFileSync(filename, body);
    return filename;
  };
  write(
    "package.json",
    JSON.stringify({
      type: "module",
      dependencies: {
        "static-dependency": "1.0.0",
        "computed-dependency": "1.0.0",
        "unused-heavy-dependency": "1.0.0",
      },
    }),
  );
  for (const name of ["static-dependency", "computed-dependency", "unused-heavy-dependency"]) {
    write(
      `node_modules/${name}/package.json`,
      JSON.stringify({ name, type: "module", main: "index.mjs" }),
    );
    write(`node_modules/${name}/index.mjs`, `export const value = '${name}-before';`);
  }
  write("helper.mjs", "export const value = 'helper-before';");
  write("lazy.mjs", "export const value = 'lazy-before';");
  write("computed.mjs", "export const value = 'computed-before';");
  write("asset.txt", "asset-before");
  write("unrelated-runtime.mjs", "throw new Error('unrelated runtime must stay unloaded');");
  write(
    `${basename}.mjs`,
    `import { value } from './helper.mjs';
     import { readFileSync } from 'node:fs';
     import { value as dependency } from 'static-dependency';
     export const readCapturedAsset = () => readFileSync(new URL('./' + ['asset', 'txt'].join('.'), import.meta.url), 'utf8');
     export const stateMigrations = [{
       id: 'fixture-state', label: 'Fixture state',
       async detectLegacyState() {
         return { preview: [value, dependency, (await import('./lazy.mjs')).value,
           (await import(['./', 'computed.mjs'].join(''))).value,
           (await import(['computed', '-dependency'].join(''))).value,
           readCapturedAsset()] };
       },
       migrateLegacyState() { return { changes: [value], warnings: [] }; },
     }];`,
  );
  const record = createPluginManifestRecordFixture({
    id: "capture-fixture",
    rootDir,
    source,
    origin: "config",
    doctorContract: { stateMigrations: [{ id: "fixture-state" }] },
  });
  const manifestRegistry = { plugins: [record], diagnostics: [] };
  return { rootDir, source, write, record, manifestRegistry };
}

it("captures the dedicated Doctor graph without walking unused declared dependency bodies", async () => {
  const { rootDir, source, write, manifestRegistry } = fixture();
  await using cache = createPluginCache();
  const readdir = vi.spyOn(fs, "readdirSync");
  const entries = (() => {
    try {
      const result = withPluginCache(cache, () =>
        listPluginDoctorStateMigrationEntries({ manifestRegistry }),
      );
      expect(
        readdir.mock.calls.some(([directory]) =>
          String(directory).includes("unused-heavy-dependency"),
        ),
      ).toBe(false);
      return result;
    } finally {
      readdir.mockRestore();
    }
  })();
  const entry = expectDefined(entries[0], "dedicated Doctor migration");
  const instance = expectDefined([...cache.setupModules.values()][0], "Doctor module owner");
  expect(instance?.hasModuleSource(source)).toBe(true);
  expect(instance?.hasModuleSource(path.join(rootDir, "helper.mjs"))).toBe(true);
  expect(instance?.hasModuleSource(path.join(rootDir, "lazy.mjs"))).toBe(true);
  expect(instance.hasModuleSource(path.join(rootDir, "unrelated-runtime.mjs"))).toBe(true);
  const mod = instance.loadModule(source) as { readCapturedAsset(): string };
  expect(getPluginValueInstance(mod.readCapturedAsset)).toBe(instance);

  write("helper.mjs", "export const value = 'helper-after';");
  write("lazy.mjs", "export const value = 'lazy-after';");
  write("computed.mjs", "export const value = 'computed-after';");
  write("asset.txt", "asset-after");
  write("node_modules/static-dependency/index.mjs", "export const value = 'static-after';");
  write("node_modules/computed-dependency/index.mjs", "export const value = 'computed-after';");
  write("doctor-contract-api.mjs", "throw new Error('replacement entry must not execute');");
  const input = {
    config: {},
    env: {},
    stateDir: rootDir,
    oauthDir: rootDir,
    context: {
      openPluginStateKeyedStore() {
        throw new Error("fixture must not open state");
      },
    },
  };
  await expect(entry.migration.detectLegacyState(input)).resolves.toEqual({
    preview: [
      "helper-before",
      "static-dependency-before",
      "lazy-before",
      "computed-before",
      "computed-dependency-before",
      "asset-before",
    ],
  });
  expect(instance?.hasModuleSource(path.join(rootDir, "computed.mjs"))).toBe(true);
  await retirePluginCache(cache);
  expect(() => mod.readCapturedAsset()).toThrow("reloaded or disabled");
});

it("retains whole-package capture for the broader legacy contract-api fallback", async () => {
  const { rootDir, source, manifestRegistry } = fixture("contract-api");
  await using cache = createPluginCache();
  const readdir = vi.spyOn(fs, "readdirSync");
  const entries = (() => {
    try {
      const result = withPluginCache(cache, () =>
        listPluginDoctorStateMigrationEntries({ manifestRegistry }),
      );
      expect(
        readdir.mock.calls.some(([directory]) =>
          String(directory).includes("unused-heavy-dependency"),
        ),
      ).toBe(true);
      return result;
    } finally {
      readdir.mockRestore();
    }
  })();
  expect(entries).toHaveLength(1);
  const instance = [...cache.setupModules.values()][0];
  expect(instance?.hasModuleSource(source)).toBe(true);
  expect(instance?.hasModuleSource(path.join(rootDir, "unrelated-runtime.mjs"))).toBe(true);
});

it("keeps deferred and complete dependency setup loaders distinct within one inventory", async () => {
  const { rootDir, source, record } = fixture();
  await using cache = createPluginCache();
  withPluginCache(cache, () => {
    getPluginSetupModuleLoader(record, source, rootDir, { deferDeclaredDependencyBodies: true });
    getPluginSetupModuleLoader(record, source, rootDir);
    getPluginSetupModuleLoader(record, source, rootDir, { deferDeclaredDependencyBodies: true });
  });
  expect(cache.setupModules.size).toBe(2);
  expect(
    [...cache.setupModules.values()].map((instance) =>
      instance.hasModuleSource(path.join(rootDir, "unrelated-runtime.mjs")),
    ),
  ).toEqual([true, true]);
});

it("preserves captured package assets and dependency admission across setup recovery", async () => {
  const { rootDir, source, record } = fixture();
  await using previousCache = createPluginCache();
  const previousLoader = withPluginCache(previousCache, () =>
    getPluginSetupModuleLoader(record, source, rootDir, { deferDeclaredDependencyBodies: true }),
  );
  previousLoader(source);
  const previous = expectDefined([...previousCache.setupModules.values()][0], "previous owner");
  const recovery = previous.captureModuleLoaderRecovery();
  await using recoveredCache = createPluginCache();
  const recovered = new PluginInstance(record.id, { cache: recoveredCache });
  try {
    fs.rmSync(rootDir, { recursive: true, force: true });
    await retirePluginCache(previousCache);
    withPluginCache(recoveredCache, () => recovery.bind(recovered));
    const mod = recovered.loadModule(source) as { readCapturedAsset(): string };
    expect(mod.readCapturedAsset()).toBe("asset-before");
    expect(getPluginValueInstance(mod.readCapturedAsset)).toBe(recovered);
  } finally {
    await recovered.dispose();
    recovery.dispose();
  }
});

it("still rejects missing required dependencies before publishing modern Doctor callbacks", async () => {
  const { rootDir, source, record } = fixture();
  fs.rmSync(path.join(rootDir, "node_modules", "unused-heavy-dependency"), {
    recursive: true,
    force: true,
  });
  await using cache = createPluginCache();
  expect(() =>
    withPluginCache(cache, () =>
      getPluginSetupModuleLoader(record, source, rootDir, { deferDeclaredDependencyBodies: true }),
    ),
  ).toThrow("Plugin dependency unused-heavy-dependency is missing");
  expect(cache.setupModules.size).toBe(0);
});
