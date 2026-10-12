/// <reference types="vite/client" />
// Regression guard: every background job is OFF until the owner deliberately switches a group on.
import { describe, expect, test } from "vitest";
import crons, { JOB_SWITCHES } from "./crons";

describe("background jobs", () => {
  test("every switch is false", () => {
    for (const [name, value] of Object.entries(JOB_SWITCHES)) expect(value, name).toBe(false);
  });

  test("no cron is registered while the switches are off", () => {
    const registered = Object.keys((crons as any).crons ?? {});
    expect(registered).toEqual([]);
  });
});
