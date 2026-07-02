using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace JVoice.App.UI;

public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c)
        => (value is bool b && b) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type t, object p, CultureInfo c)
        => value is Visibility v && v == Visibility.Collapsed;
}

/// [fraction (0..1), containerWidth] → an absolute pixel width, so a plain Border can act as a
/// progress-bar fill (the in-app updater's eased download bar). Clamps the fraction to [0,1] and
/// tolerates NaN / an unmeasured (0-width) container by returning 0.
public sealed class FractionToWidthConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type t, object p, CultureInfo c)
    {
        if (values.Length < 2) return 0.0;
        double frac = ToDouble(values[0]);
        double width = ToDouble(values[1]);
        if (double.IsNaN(frac) || double.IsNaN(width) || width <= 0) return 0.0;
        frac = frac < 0 ? 0 : frac > 1 ? 1 : frac;
        return frac * width;
    }

    public object[] ConvertBack(object value, Type[] t, object p, CultureInfo c)
        => throw new NotSupportedException();

    private static double ToDouble(object? o)
        => o is double d ? d : o is IConvertible ? System.Convert.ToDouble(o, CultureInfo.InvariantCulture) : 0.0;
}
