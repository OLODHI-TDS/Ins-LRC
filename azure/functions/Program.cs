using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Communication.Email;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices((context, services) =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        // Register Key Vault client
        var keyVaultUrl = Environment.GetEnvironmentVariable("KeyVaultUrl")
            ?? "https://kv-landreg.vault.azure.net/";
        var secretClient = new SecretClient(new Uri(keyVaultUrl), new DefaultAzureCredential());
        services.AddSingleton(secretClient);

        // Register Email client (lazy initialization from Key Vault)
        services.AddSingleton<EmailClient>(sp =>
        {
            var secrets = sp.GetRequiredService<SecretClient>();
            var connectionString = secrets.GetSecret("acs-connection-string").Value.Value;
            return new EmailClient(connectionString);
        });
    })
    .Build();

host.Run();
