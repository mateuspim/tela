import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/data/localsend/localsend_wire.dart';

/// Asks for a receiver's address, for networks discovery cannot cross.
///
/// Multicast does not survive every network — a guest VLAN, an access point
/// with client isolation, a router filtering `224.0.0.0/24` — and on those a
/// typed address is the only way through.
///
/// The port is prefilled with LocalSend's registered one, because it is what
/// every default install listens on and asking for it is a question almost
/// nobody has a different answer to.
class BeamAddressDialog extends StatefulWidget {
  /// Creates the dialog.
  const BeamAddressDialog({super.key});

  @override
  State<BeamAddressDialog> createState() => _BeamAddressDialogState();
}

class _BeamAddressDialogState extends State<BeamAddressDialog> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(
    text: '${LocalSendIdentity.defaultPort}',
  );

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.beamEnterAddress),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: l10n.beamAddressHint),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.actionSave)),
      ],
    );
  }

  /// Closes with the typed address, or does nothing if it cannot be one.
  ///
  /// Refusing silently rather than showing an error: the only ways to fail
  /// here are an empty host or a cleared port, both of which the user can see
  /// they have done.
  void _submit() {
    final String host = _host.text.trim();
    final int? port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null) return;
    Navigator.of(context).pop((host: host, port: port));
  }
}
