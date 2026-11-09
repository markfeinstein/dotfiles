{
  variant ? "rose-pine",
  name ? variant,
}: let
  theme = import ./theme.nix;
  colors = theme.colors variant;
  rosevars =
    colors
    // {
      hlLow = colors.highlightLow;
      hlMed = colors.highlightMed;
      hlHigh = colors.highlightHigh;
      # Keep Pi's message and tool surfaces within the official palette rather
      # than carrying dark-only blended colors into Moon or Dawn.
      customBg = colors.surface;
      pendingBg = colors.highlightLow;
      successBg = colors.highlightLow;
      errorBg = colors.highlightLow;
    };
in {
  "$schema" = "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
  inherit name;
  vars = rosevars;
  colors = {
    accent = "iris";
    border = "pine";
    borderAccent = "foam";
    borderMuted = "hlMed";
    success = "pine";
    error = "love";
    warning = "gold";
    muted = "muted";
    dim = "muted";
    text = "text";
    thinkingText = "subtle";
    selectedBg = "hlMed";
    scrollbarThumb = "hlHigh";
    userMessageBg = "overlay";
    userMessageText = "text";
    customMessageBg = "customBg";
    customMessageText = "text";
    customMessageLabel = "iris";
    toolPendingBg = "pendingBg";
    toolSuccessBg = "successBg";
    toolErrorBg = "errorBg";
    toolTitle = "text";
    toolOutput = "subtle";
    mdHeading = "gold";
    mdLink = "foam";
    mdLinkUrl = "muted";
    mdCode = "rose";
    mdCodeBlock = "foam";
    mdCodeBlockBorder = "hlMed";
    mdQuote = "subtle";
    mdQuoteBorder = "muted";
    mdHr = "muted";
    mdListBullet = "iris";
    toolDiffAdded = "pine";
    toolDiffRemoved = "love";
    toolDiffContext = "subtle";
    syntaxComment = "muted";
    syntaxKeyword = "pine";
    syntaxFunction = "rose";
    syntaxVariable = "text";
    syntaxString = "gold";
    syntaxNumber = "gold";
    syntaxType = "foam";
    syntaxOperator = "subtle";
    syntaxPunctuation = "subtle";
    thinkingOff = "muted";
    thinkingMinimal = "subtle";
    thinkingLow = "foam";
    thinkingMedium = "pine";
    thinkingHigh = "iris";
    thinkingXhigh = "love";
    thinkingMax = "love";
    bashMode = "foam";
  };
  export = {
    pageBg = colors.base;
    cardBg = colors.surface;
    infoBg = colors.highlightLow;
  };
}
