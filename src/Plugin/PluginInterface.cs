using Jellyfin.Plugin.FileTransformation.Helpers;
using Jellyfin.Plugin.FileTransformation.Library;
using Jellyfin.Plugin.FileTransformation.Models;
using MediaBrowser.Controller;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace Jellyfin.Plugin.FileTransformation
{
    public static class PluginInterface
    {
        public static void RegisterTransformation(JObject payload)
        {
            IWebFileTransformationWriteService writeService = FileTransformationPlugin.Instance.ServiceProvider
                .GetRequiredService<IWebFileTransformationWriteService>();

            TransformationRegistrationPayload? castedPayload = payload.ToObject<TransformationRegistrationPayload>();

            if (castedPayload != null)
            {
                // Resolve services eagerly at registration time. The ServiceProvider captured
                // by the plugin is scoped and will be disposed after startup. Resolving lazily
                // inside the callback causes ObjectDisposedException on every subsequent request.
                // Both ILogger and IServerApplicationHost are singletons, so capturing them here is safe.
                ILogger logger = FileTransformationPlugin.Instance.ServiceProvider.GetRequiredService<IFileTransformationLogger>();
                IServerApplicationHost serverApplicationHost = FileTransformationPlugin.Instance.ServiceProvider.GetRequiredService<IServerApplicationHost>();

                writeService.AddTransformation(castedPayload.Id, castedPayload.FileNamePattern, async (path, contents) =>
                {
                    await TransformationHelper.ApplyTransformation(path, contents, castedPayload, logger, serverApplicationHost);
                });
            }
        }
    }
}