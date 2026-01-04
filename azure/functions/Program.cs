using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Communication.Email;
using Azure.Storage.Blobs;

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

        // Register Blob Service client for document storage
        var blobConnectionString = Environment.GetEnvironmentVariable("BLOB_STORAGE_CONNECTION_STRING")
            ?? Environment.GetEnvironmentVariable("AzureWebJobsStorage")
            ?? "UseDevelopmentStorage=true";
        services.AddSingleton(new BlobServiceClient(blobConnectionString));
    })
    .Build();

host.Run();
