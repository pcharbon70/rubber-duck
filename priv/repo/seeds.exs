# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     RubberDuck.Repo.insert!(%RubberDuck.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Seed preference defaults
IO.puts("Seeding preference defaults...")

# Seed LLM provider defaults
case RubberDuck.Preferences.Seeders.LlmDefaultsSeeder.seed_all() do
  :ok -> IO.puts("✅ LLM defaults seeded successfully")
  {:error, reason} -> IO.puts("❌ Failed to seed LLM defaults: #{inspect(reason)}")
end

# Seed budget defaults
case RubberDuck.Preferences.Seeders.BudgetDefaultsSeeder.seed_all() do
  :ok -> IO.puts("✅ Budget defaults seeded successfully")  
  {:error, reason} -> IO.puts("❌ Failed to seed budget defaults: #{inspect(reason)}")
end

# Seed ML defaults
case RubberDuck.Preferences.Seeders.MlDefaultsSeeder.seed_all() do
  :ok -> IO.puts("✅ ML defaults seeded successfully")
  {:error, reason} -> IO.puts("❌ Failed to seed ML defaults: #{inspect(reason)}")
end

IO.puts("Seeding completed!")
