// Namiastka D1 na node:sqlite: ten sam SQL i te same wywołania (prepare/bind/first/all/run), bez wranglera.
import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync } from "node:fs";

export function createD1() {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys = ON");
  const dir = new URL("../migrations/", import.meta.url);
  for (const file of readdirSync(dir).filter(f => f.endsWith(".sql")).sort()) db.exec(readFileSync(new URL(file, dir), "utf8"));
  const statement = (sql, params) => ({
    bind(...values) {
      // D1 odrzuca undefined; łapiemy to tutaj, zanim zrobi to produkcja
      if (values.some(v => v === undefined)) throw new TypeError(`undefined bound in: ${sql}`);
      return statement(sql, values);
    },
    async first(column) {
      const row = db.prepare(sql).get(...params);
      if (row === undefined) return null;
      return column ? row[column] : { ...row };
    },
    async all() {
      return { results: db.prepare(sql).all(...params).map(row => ({ ...row })) };
    },
    async run() {
      const info = db.prepare(sql).run(...params);
      return { success: true, meta: { changes: Number(info.changes) } };
    },
  });
  return { prepare: sql => statement(sql, []), raw: db };
}
