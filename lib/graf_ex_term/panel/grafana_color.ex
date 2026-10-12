defmodule GrafExTerm.Panel.GrafanaColor do
  @moduledoc """
  Resolves a colour as a Grafana dashboard writes it to `{r, g, b}`.

  Accepted, in the order Grafana itself looks them up:

    * the shade names of Grafana's dark theme — `super-light-`, `light-`, plain,
      `semi-dark-` and `dark-` for each of red, orange, yellow, green, blue and
      purple, e.g. `"semi-dark-green"`
    * the CSS named colours, case-insensitively, e.g. `"cornflowerblue"`
    * `#rgb`, `#rrggbb`, `rgb()`, `rgba()`, `hsl()` and `hsla()`; alpha is dropped

  `"transparent"`, `"text"`, `"panel-bg"`, `nil` and anything else resolve to `nil`,
  meaning "no colour of its own".

      iex> GrafExTerm.Panel.GrafanaColor.resolve("semi-dark-green")
      {86, 166, 75}

      iex> GrafExTerm.Panel.GrafanaColor.resolve("rgba(50, 172, 45, 0.97)")
      {50, 172, 45}

      iex> GrafExTerm.Panel.GrafanaColor.resolve("Tomato")
      {255, 99, 71}

      iex> GrafExTerm.Panel.GrafanaColor.resolve("transparent")
      nil

  """

  @type rgb :: {byte(), byte(), byte()}

  @shades %{
    "red" => ["#FFA6B0", "#FF7383", "#F2495C", "#E02F44", "#C4162A"],
    "orange" => ["#FFCB7D", "#FFB357", "#FF9830", "#FF780A", "#FA6400"],
    "yellow" => ["#FFF899", "#FFEE52", "#FADE2A", "#F2CC0C", "#E0B400"],
    "green" => ["#C8F2C2", "#96D98D", "#73BF69", "#56A64B", "#37872D"],
    "blue" => ["#C0D8FF", "#8AB8FF", "#5794F2", "#3274D9", "#1F60C4"],
    "purple" => ["#DEB6F2", "#CA95E5", "#B877D9", "#A352CC", "#8F3BB8"]
  }

  @shade_prefixes ["super-light-", "light-", "", "semi-dark-", "dark-"]

  @grafana_names (for {hue, hexes} <- @shades,
                      {prefix, "#" <> hex} <- Enum.zip(@shade_prefixes, hexes),
                      into: %{} do
                    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex

                    {prefix <> hue,
                     {String.to_integer(r, 16), String.to_integer(g, 16),
                      String.to_integer(b, 16)}}
                  end)

  @css_names %{
    "aliceblue" => {240, 248, 255},
    "antiquewhite" => {250, 235, 215},
    "aqua" => {0, 255, 255},
    "aquamarine" => {127, 255, 212},
    "azure" => {240, 255, 255},
    "beige" => {245, 245, 220},
    "bisque" => {255, 228, 196},
    "black" => {0, 0, 0},
    "blanchedalmond" => {255, 235, 205},
    "blue" => {0, 0, 255},
    "blueviolet" => {138, 43, 226},
    "brown" => {165, 42, 42},
    "burlywood" => {222, 184, 135},
    "cadetblue" => {95, 158, 160},
    "chartreuse" => {127, 255, 0},
    "chocolate" => {210, 105, 30},
    "coral" => {255, 127, 80},
    "cornflowerblue" => {100, 149, 237},
    "cornsilk" => {255, 248, 220},
    "crimson" => {220, 20, 60},
    "cyan" => {0, 255, 255},
    "darkblue" => {0, 0, 139},
    "darkcyan" => {0, 139, 139},
    "darkgoldenrod" => {184, 134, 11},
    "darkgray" => {169, 169, 169},
    "darkgreen" => {0, 100, 0},
    "darkgrey" => {169, 169, 169},
    "darkkhaki" => {189, 183, 107},
    "darkmagenta" => {139, 0, 139},
    "darkolivegreen" => {85, 107, 47},
    "darkorange" => {255, 140, 0},
    "darkorchid" => {153, 50, 204},
    "darkred" => {139, 0, 0},
    "darksalmon" => {233, 150, 122},
    "darkseagreen" => {143, 188, 143},
    "darkslateblue" => {72, 61, 139},
    "darkslategray" => {47, 79, 79},
    "darkslategrey" => {47, 79, 79},
    "darkturquoise" => {0, 206, 209},
    "darkviolet" => {148, 0, 211},
    "deeppink" => {255, 20, 147},
    "deepskyblue" => {0, 191, 255},
    "dimgray" => {105, 105, 105},
    "dimgrey" => {105, 105, 105},
    "dodgerblue" => {30, 144, 255},
    "firebrick" => {178, 34, 34},
    "floralwhite" => {255, 250, 240},
    "forestgreen" => {34, 139, 34},
    "fuchsia" => {255, 0, 255},
    "gainsboro" => {220, 220, 220},
    "ghostwhite" => {248, 248, 255},
    "gold" => {255, 215, 0},
    "goldenrod" => {218, 165, 32},
    "gray" => {128, 128, 128},
    "green" => {0, 128, 0},
    "greenyellow" => {173, 255, 47},
    "grey" => {128, 128, 128},
    "honeydew" => {240, 255, 240},
    "hotpink" => {255, 105, 180},
    "indianred" => {205, 92, 92},
    "indigo" => {75, 0, 130},
    "ivory" => {255, 255, 240},
    "khaki" => {240, 230, 140},
    "lavender" => {230, 230, 250},
    "lavenderblush" => {255, 240, 245},
    "lawngreen" => {124, 252, 0},
    "lemonchiffon" => {255, 250, 205},
    "lightblue" => {173, 216, 230},
    "lightcoral" => {240, 128, 128},
    "lightcyan" => {224, 255, 255},
    "lightgoldenrodyellow" => {250, 250, 210},
    "lightgray" => {211, 211, 211},
    "lightgreen" => {144, 238, 144},
    "lightgrey" => {211, 211, 211},
    "lightpink" => {255, 182, 193},
    "lightsalmon" => {255, 160, 122},
    "lightseagreen" => {32, 178, 170},
    "lightskyblue" => {135, 206, 250},
    "lightslategray" => {119, 136, 153},
    "lightslategrey" => {119, 136, 153},
    "lightsteelblue" => {176, 196, 222},
    "lightyellow" => {255, 255, 224},
    "lime" => {0, 255, 0},
    "limegreen" => {50, 205, 50},
    "linen" => {250, 240, 230},
    "magenta" => {255, 0, 255},
    "maroon" => {128, 0, 0},
    "mediumaquamarine" => {102, 205, 170},
    "mediumblue" => {0, 0, 205},
    "mediumorchid" => {186, 85, 211},
    "mediumpurple" => {147, 112, 219},
    "mediumseagreen" => {60, 179, 113},
    "mediumslateblue" => {123, 104, 238},
    "mediumspringgreen" => {0, 250, 154},
    "mediumturquoise" => {72, 209, 204},
    "mediumvioletred" => {199, 21, 133},
    "midnightblue" => {25, 25, 112},
    "mintcream" => {245, 255, 250},
    "mistyrose" => {255, 228, 225},
    "moccasin" => {255, 228, 181},
    "navajowhite" => {255, 222, 173},
    "navy" => {0, 0, 128},
    "oldlace" => {253, 245, 230},
    "olive" => {128, 128, 0},
    "olivedrab" => {107, 142, 35},
    "orange" => {255, 165, 0},
    "orangered" => {255, 69, 0},
    "orchid" => {218, 112, 214},
    "palegoldenrod" => {238, 232, 170},
    "palegreen" => {152, 251, 152},
    "paleturquoise" => {175, 238, 238},
    "palevioletred" => {219, 112, 147},
    "papayawhip" => {255, 239, 213},
    "peachpuff" => {255, 218, 185},
    "peru" => {205, 133, 63},
    "pink" => {255, 192, 203},
    "plum" => {221, 160, 221},
    "powderblue" => {176, 224, 230},
    "purple" => {128, 0, 128},
    "rebeccapurple" => {102, 51, 153},
    "red" => {255, 0, 0},
    "rosybrown" => {188, 143, 143},
    "royalblue" => {65, 105, 225},
    "saddlebrown" => {139, 69, 19},
    "salmon" => {250, 128, 114},
    "sandybrown" => {244, 164, 96},
    "seagreen" => {46, 139, 87},
    "seashell" => {255, 245, 238},
    "sienna" => {160, 82, 45},
    "silver" => {192, 192, 192},
    "skyblue" => {135, 206, 235},
    "slateblue" => {106, 90, 205},
    "slategray" => {112, 128, 144},
    "slategrey" => {112, 128, 144},
    "snow" => {255, 250, 250},
    "springgreen" => {0, 255, 127},
    "steelblue" => {70, 130, 180},
    "tan" => {210, 180, 140},
    "teal" => {0, 128, 128},
    "thistle" => {216, 191, 216},
    "tomato" => {255, 99, 71},
    "turquoise" => {64, 224, 208},
    "violet" => {238, 130, 238},
    "wheat" => {245, 222, 179},
    "white" => {255, 255, 255},
    "whitesmoke" => {245, 245, 245},
    "yellow" => {255, 255, 0},
    "yellowgreen" => {154, 205, 50}
  }

  @doc """
  The `{r, g, b}` for a Grafana colour string, or `nil` when it names no colour.
  """
  @spec resolve(term()) :: rgb() | nil
  def resolve(name) when is_binary(name) do
    trimmed = String.trim(name)

    Map.get(@grafana_names, trimmed) ||
      Map.get(@css_names, String.downcase(trimmed)) ||
      parse(trimmed)
  end

  def resolve(_other), do: nil

  defp parse(text) do
    case Drafter.Color.parse(text) do
      {:ok, color} -> Drafter.Color.to_tuple(color)
      _not_a_colour -> nil
    end
  end
end
