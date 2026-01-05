using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Communication.Email;
using Azure.Storage.Blobs;
using Microsoft.Graph;
using LandRegFunctions.Models;

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

        // Register Microsoft Graph client for inbox monitoring
        services.AddSingleton<GraphServiceClient>(sp =>
        {
            var secrets = sp.GetRequiredService<SecretClient>();

            // Get M365 credentials from Key Vault
            var tenantId = secrets.GetSecret("m365-tenant-id").Value.Value;
            var clientId = secrets.GetSecret("m365-client-id").Value.Value;
            var clientSecret = secrets.GetSecret("m365-client-secret").Value.Value;

            // Create client credential
            var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);

            // Create Graph client
            return new GraphServiceClient(credential, new[] { "https://graph.microsoft.com/.default" });
        });

        // Register mailbox address for inbox monitoring
        services.AddSingleton<MailboxSettings>(sp =>
        {
            var secrets = sp.GetRequiredService<SecretClient>();
            var mailboxAddress = secrets.GetSecret("m365-mailbox-address").Value.Value;
            return new MailboxSettings { MailboxAddress = mailboxAddress };
        });
    })
    .Build();

host.Run();
