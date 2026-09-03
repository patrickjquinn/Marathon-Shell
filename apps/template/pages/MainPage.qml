import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// The scaffold app developers copy. It hand-rolled a title bar and a scroll
// view that MPage already provides, and set `content:` on MActionBar -- a
// property MActionBar does not have, so the title never rendered. Nothing
// caught it because `template` is deliberately absent from apps/CMakeLists.txt
// (it must not ship on the home grid), so it is never built.
//
// MPage gives you the title bar, the scrolling content area and the safe-area
// insets. Put your content in `content:` and let it do that work.
MPage {
    id: mainPage

    title: "Template App"

    content: [
        Column {
            width: mainPage.width
            padding: MSpacing.lg
            spacing: MSpacing.lg

                    MEmptyState {
                        width: parent.width - parent.padding * 2
                        height: 400
                        iconName: "package"
                        iconSize: 96
                        title: "Template App"
                        message: "Replace this with your app content. See docs/MAPP_GUIDE.md for best practices."
                    }

                    MCard {
                        width: parent.width - parent.padding * 2
                        elevation: 1
                        interactive: true
                        onClicked: {
                            HapticService.light();
                            Logger.info("TemplateApp", "Card clicked");
                        }

                        Column {
                            width: parent.parent.width - MSpacing.md * 2
                            padding: MSpacing.md
                            spacing: MSpacing.sm

                            Row {
                                width: parent.width - parent.padding * 2
                                spacing: MSpacing.md

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "info"
                                    size: Constants.iconSizeMedium
                                    color: MColors.accent
                                }

                                Column {
                                    width: parent.width - parent.spacing - Constants.iconSizeMedium
                                    spacing: MSpacing.xs

                                    MLabel {
                                        text: "Example Card"
                                        variant: "primary"
                                        font.weight: Font.DemiBold
                                    }

                                    MLabel {
                                        text: "This is an example of a Marathon UI card component. Tap to interact."
                                        variant: "secondary"
                                        wrapMode: Text.WordWrap
                                        width: parent.width
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width - parent.padding * 2
                        spacing: MSpacing.md

                        MButton {
                            text: "Primary"
                            variant: "primary"
                            onClicked: {
                                HapticService.medium();
                                Logger.info("TemplateApp", "Primary button clicked");
                            }
                        }

                        MButton {
                            text: "Secondary"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light();
                                Logger.info("TemplateApp", "Secondary button clicked");
                            }
                        }
            }
        }
    ]
}
