Logger.configure(level: :info)
Application.load(:event_store)

for app <- Application.spec(:event_store, :applications) do
  Application.ensure_all_started(app)
end

ExUnit.start()
