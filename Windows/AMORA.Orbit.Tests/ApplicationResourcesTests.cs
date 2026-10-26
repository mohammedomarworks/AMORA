using System.IO;
using System.Linq;
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
}
