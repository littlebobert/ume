import { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const migrationsDirectory = fileURLToPath(new URL('../migrations/', import.meta.url));

function statementAdapter(database, sql, bindings = []) {
  return {
    bind(...values) {
      return statementAdapter(database, sql, values);
    },
    async all() {
      return { results: database.prepare(sql).all(...bindings) };
    },
    async first() {
      return database.prepare(sql).get(...bindings) || null;
    },
    async run() {
      const result = database.prepare(sql).run(...bindings);
      return {
        meta: {
          changes: Number(result.changes),
          last_row_id: Number(result.lastInsertRowid),
        },
      };
    },
  };
}

export function createTestDatabase() {
  const database = new DatabaseSync(':memory:');
  readdirSync(migrationsDirectory)
    .filter((fileName) => fileName.endsWith('.sql'))
    .sort()
    .forEach((fileName) => {
      database.exec(readFileSync(`${migrationsDirectory}/${fileName}`, 'utf8'));
    });
  return {
    database,
    d1: {
      prepare(sql) {
        return statementAdapter(database, sql);
      },
    },
  };
}
