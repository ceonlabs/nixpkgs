{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "goeland";
  version = "0.17.0";

  src = fetchFromGitHub {
    owner = "slurdge";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-ISAaV1MgqnzO2fMgoZZKT8FSDq6XIRvjWG72dALY+rU=";
  };

  vendorHash = "sha256-uk1Ew77XaS/k7QXqNa70Nyynb+6pzs7B5jhusz3ffZY=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/slurdge/goeland/version.GitCommit=${version}"
  ];

  meta = with lib; {
    description = "An alternative to rss2email written in golang with many filters";
    longDescription = ''
      Goeland excels at creating beautiful emails from RSS feeds,
      tailored for daily or weekly digest. It includes a number of
      filters that can transform the RSS content along the way.
      It can also consume other sources, such as Imgur tags.
    '';
    homepage = "https://github.com/slurdge/goeland";
    changelog = "https://github.com/slurdge/goeland/blob/v${version}/CHANGELOG.md";
    license = with licenses; [ mit ];
    maintainers = [ maintainers.sweenu ];
  };
}
