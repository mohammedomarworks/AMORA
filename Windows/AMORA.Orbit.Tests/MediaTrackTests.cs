using AMORA.Orbit.Models;
using Xunit;

namespace AMORA.Orbit.Tests;

public class MediaTrackTests
{
    [Fact]
    public void FormattedTimes_FormatsMinutesAndSeconds()
    {
        var track = new MediaTrack(
            Title: "Starboy",
            Artist: "The Weeknd",
            Elapsed: TimeSpan.FromSeconds(85),
            Duration: TimeSpan.FromSeconds(230),
            Source: MediaSourceType.Spotify);

        Assert.Equal("01:25", track.FormattedElapsed);
        Assert.Equal("03:50", track.FormattedDuration);
    }

    [Fact]
    public void ProgressPercent_CalculatesRatio_ClampedBetweenZeroAndOne()
    {
        var track = new MediaTrack(
            Title: "Song",
            Artist: "Artist",
            Elapsed: TimeSpan.FromSeconds(100),
            Duration: TimeSpan.FromSeconds(200),
            Source: MediaSourceType.System);

        Assert.Equal(0.5, track.ProgressPercent, precision: 2);
    }

    [Fact]
    public void ProgressPercent_ZeroDuration_ReturnsZero()
    {
        var track = new MediaTrack(
            Title: "Stream",
            Artist: "Live",
            Elapsed: TimeSpan.FromSeconds(10),
            Duration: TimeSpan.Zero,
            Source: MediaSourceType.System);

        Assert.Equal(0.0, track.ProgressPercent);
    }
}
