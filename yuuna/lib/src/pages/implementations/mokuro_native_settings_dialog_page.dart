import 'package:flutter/material.dart';
import 'package:spaces/spaces.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// The content of the dialog used for managing native Mokuro reader settings.
class MokuroNativeSettingsDialogPage extends BasePage {
  /// Create an instance of this page.
  const MokuroNativeSettingsDialogPage({super.key});

  @override
  BasePageState createState() => _MokuroNativeSettingsDialogPageState();
}

class _MokuroNativeSettingsDialogPageState extends BasePageState {
  ReaderMokuroNativeSource get source => ReaderMokuroNativeSource.instance;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: MediaQuery.of(context).orientation == Orientation.portrait
          ? Spacing.of(context).insets.exceptBottom.big
          : Spacing.of(context).insets.exceptBottom.normal.copyWith(
                left: Spacing.of(context).spaces.semiBig,
                right: Spacing.of(context).spaces.semiBig,
              ),
      actionsPadding: Spacing.of(context).insets.exceptBottom.normal.copyWith(
            left: Spacing.of(context).spaces.normal,
            right: Spacing.of(context).spaces.normal,
            bottom: Spacing.of(context).spaces.normal,
            top: Spacing.of(context).spaces.extraSmall,
          ),
      content: buildContent(),
      actions: actions,
    );
  }

  List<Widget> get actions => [
        buildCloseButton(),
      ];

  Widget buildCloseButton() {
    return TextButton(
      child: Text(t.dialog_close),
      onPressed: () => Navigator.pop(context),
    );
  }

  Widget buildContent() {
    ScrollController contentController = ScrollController();

    return SizedBox(
      width: double.maxFinite,
      child: RawScrollbar(
        thickness: 3,
        thumbVisibility: true,
        controller: contentController,
        child: SingleChildScrollView(
          controller: contentController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildSwitch(
                label: t.mokuro_right_to_left,
                value: () => source.rightToLeft,
                onToggle: source.toggleRightToLeft,
              ),
              buildSwitch(
                label: t.mokuro_two_pages_in_landscape,
                value: () => source.twoPagesInLandscape,
                onToggle: source.toggleTwoPagesInLandscape,
              ),
              buildSwitch(
                label: t.mokuro_first_page_is_cover,
                value: () => source.firstPageIsCover,
                onToggle: source.toggleFirstPageIsCover,
              ),
              buildSwitch(
                label: t.highlight_on_tap,
                value: () => source.highlightOnTap,
                onToggle: source.toggleHighlightOnTap,
              ),
              buildSwitch(
                label: t.volume_button_page_turning,
                value: () => source.volumePageTurningEnabled,
                onToggle: source.toggleVolumePageTurningEnabled,
              ),
              buildSwitch(
                label: t.invert_volume_buttons,
                value: () => source.volumePageTurningInverted,
                onToggle: source.toggleVolumePageTurningInverted,
              ),
              buildSwitch(
                label: t.mokuro_invert_page_colours,
                value: () => source.invertPageColours,
                onToggle: source.toggleInvertPageColours,
              ),
              buildSwitch(
                label: t.mokuro_show_recognised_text,
                value: () => source.showRecognisedText,
                onToggle: source.toggleShowRecognisedText,
              ),
              buildSwitch(
                label: t.mokuro_show_text_outlines,
                value: () => source.showTextOutlines,
                onToggle: source.toggleShowTextOutlines,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSwitch({
    required String label,
    required bool Function() value,
    required VoidCallback onToggle,
  }) {
    ValueNotifier<bool> notifier = ValueNotifier<bool>(value());

    return Row(
      children: [
        Expanded(
          child: Text(label),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: notifier,
          builder: (_, enabled, __) {
            return Switch(
              value: enabled,
              onChanged: (_) {
                onToggle();
                notifier.value = value();
              },
            );
          },
        )
      ],
    );
  }
}
