using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Xunit;

namespace AMORA.Orbit.Tests;

public class ApplicationResourcesTests
{
    [Fact]
    public void AppResources_LoadWinUiControlResourcesBeforeApplicationResources()
    {
        string appXamlPath = Path.Combine(AppContext.BaseDirectory, "Fixtures", "App.xaml");
        XDocument document = XDocument.Load(appXamlPath);
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";

        XElement? appResources = document.Root?
            .Element(presentation + "Application.Resources")?
            .Element(presentation + "ResourceDictionary");
        XElement? mergedDictionaries = appResources?.Element(presentation + "ResourceDictionary.MergedDictionaries");
        XElement? firstMergedDictionary = mergedDictionaries?.Elements().FirstOrDefault();

        Assert.NotNull(firstMergedDictionary);
        Assert.Equal("XamlControlsResources", firstMergedDictionary.Name.LocalName);
        Assert.Equal("using:Microsoft.UI.Xaml.Controls", firstMergedDictionary.Name.NamespaceName);
    }

    [Fact]
    public void AllXaml_ReferencesExistingApplicationResourceKeys()
    {
        // A build can succeed even when a StaticResource fails at runtime.
        // Check our application-owned keys in every view, including lazy panels.
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";
        var appKeys = XDocument.Load(Path.Combine(fixtures, "App.xaml"))
            .Descendants().Attributes(xaml + "Key").Select(a => a.Value).ToHashSet();
        string[] views = Directory.GetFiles(Path.Combine(fixtures, "Views"), "*.xaml");
        Assert.NotEmpty(views);
        foreach (string view in views.Concat(new[] { Path.Combine(fixtures, "App.xaml"), Path.Combine(fixtures, "MainWindow.xaml") }))
        {
            XDocument document = XDocument.Load(view);
            foreach (XAttribute attribute in document.Descendants().Attributes())
            {
                foreach (Match match in Regex.Matches(attribute.Value, @"\{(?:StaticResource|ThemeResource)\s+([^\s}]+)\s*\}"))
                {
                    string key = match.Groups[1].Value;
                    if (key.StartsWith("Orbit", StringComparison.Ordinal) || key == "BoolToVis")
                    {
                        Assert.True(appKeys.Contains(key), $"{Path.GetFileName(view)} references missing application resource '{key}'.");
                    }
                }
            }
        }
    }
}
