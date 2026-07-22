import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

/// A modal bottom sheet for creating or editing a reusable [Venue].
///
/// A venue is a **shared** record: the same row is referenced by every program
/// held there (via `Program.venueId`), so a change here is visible on all of
/// them. The sheet performs no persistence itself — it returns the built
/// [Venue] via [Navigator.pop] when the user saves (or `null` when
/// cancelled/dismissed) and the caller upserts it, so the sheet stays trivially
/// testable (mirrors `ChoreographerDetailsDialog`).
///
/// The [Venue] model trims and normalizes empty/whitespace optional fields to
/// `null`, so the controllers' raw text is passed straight through; only [name]
/// is validated to be non-empty.
class VenueEditorSheet extends StatefulWidget {
  const VenueEditorSheet({super.key, this.initial, this.seedName});

  /// The venue to edit; fields prefill from it. When `null` the sheet is in
  /// create mode and mints a fresh id on save.
  final Venue? initial;

  /// In create mode ([initial] `null`), prefills the name field with this text
  /// (e.g. what the user typed in the picker before choosing "Add new venue…").
  /// Ignored when editing an existing venue.
  final String? seedName;

  /// Opens the sheet for [initial] (or a new venue when `initial` is null),
  /// resolving to the built [Venue] or `null` if the user cancels. Pass
  /// [seedName] to prefill the name of a new venue.
  static Future<Venue?> show(
    BuildContext context, {
    Venue? initial,
    String? seedName,
  }) {
    return showModalBottomSheet<Venue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => VenueEditorSheet(initial: initial, seedName: seedName),
    );
  }

  @override
  State<VenueEditorSheet> createState() => _VenueEditorSheetState();
}

class _VenueEditorSheetState extends State<VenueEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _website;
  late final TextEditingController _sponsor;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _stateProv;
  late final TextEditingController _country;
  late final TextEditingController _postalCode;
  late final TextEditingController _plus4;
  late final TextEditingController _eventName;
  late final TextEditingController _time;
  late final TextEditingController _genericSchedule;
  late final TextEditingController _price;
  late final TextEditingController _contact1Name;
  late final TextEditingController _contact1Phone;
  late final TextEditingController _contact1Email;
  late final TextEditingController _contact2Name;
  late final TextEditingController _contact2Phone;
  late final TextEditingController _contact2Email;
  late final TextEditingController _notes;

  late final List<TextEditingController> _all;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _name = TextEditingController(text: v?.name ?? widget.seedName ?? '');
    _website = TextEditingController(text: v?.website ?? '');
    _sponsor = TextEditingController(text: v?.sponsor ?? '');
    _address1 = TextEditingController(text: v?.address1 ?? '');
    _address2 = TextEditingController(text: v?.address2 ?? '');
    _city = TextEditingController(text: v?.city ?? '');
    _stateProv = TextEditingController(text: v?.stateProv ?? '');
    _country = TextEditingController(text: v?.country ?? '');
    _postalCode = TextEditingController(text: v?.postalCode ?? '');
    _plus4 = TextEditingController(text: v?.plus4 ?? '');
    _eventName = TextEditingController(text: v?.eventName ?? '');
    _time = TextEditingController(text: v?.time ?? '');
    _genericSchedule = TextEditingController(text: v?.genericSchedule ?? '');
    _price = TextEditingController(text: v?.price ?? '');
    _contact1Name = TextEditingController(text: v?.contact1Name ?? '');
    _contact1Phone = TextEditingController(text: v?.contact1Phone ?? '');
    _contact1Email = TextEditingController(text: v?.contact1Email ?? '');
    _contact2Name = TextEditingController(text: v?.contact2Name ?? '');
    _contact2Phone = TextEditingController(text: v?.contact2Phone ?? '');
    _contact2Email = TextEditingController(text: v?.contact2Email ?? '');
    _notes = TextEditingController(text: v?.notes ?? '');
    _all = [
      _name,
      _website,
      _sponsor,
      _address1,
      _address2,
      _city,
      _stateProv,
      _country,
      _postalCode,
      _plus4,
      _eventName,
      _time,
      _genericSchedule,
      _price,
      _contact1Name,
      _contact1Phone,
      _contact1Email,
      _contact2Name,
      _contact2Phone,
      _contact2Email,
      _notes,
    ];
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    // Build a fresh record from the controllers so clearing an optional field
    // actually clears it. The Venue constructor normalizes empty/whitespace to
    // null, so raw text is safe to pass through; id carries over (or is minted
    // for a new venue).
    final venue = Venue(
      id: widget.initial?.id ?? uuidV4(),
      name: _name.text.trim(),
      website: _website.text,
      sponsor: _sponsor.text,
      address1: _address1.text,
      address2: _address2.text,
      city: _city.text,
      stateProv: _stateProv.text,
      country: _country.text,
      postalCode: _postalCode.text,
      plus4: _plus4.text,
      eventName: _eventName.text,
      time: _time.text,
      genericSchedule: _genericSchedule.text,
      price: _price.text,
      contact1Name: _contact1Name.text,
      contact1Phone: _contact1Phone.text,
      contact1Email: _contact1Email.text,
      contact2Name: _contact2Name.text,
      contact2Phone: _contact2Phone.text,
      contact2Email: _contact2Email.text,
      notes: _notes.text,
    );
    Navigator.of(context).pop(venue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.initial == null;
    // Pad for the on-screen keyboard so the focused field stays visible.
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isNew ? 'New venue' : 'Edit venue',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A venue is shared across every program held here, so '
                        'edits to its address, contacts, or schedule show up on '
                        'all of them.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        keyName: 'venue-name-field',
                        controller: _name,
                        label: 'Name *',
                        autofocus: isNew,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      _field(
                        keyName: 'venue-website-field',
                        controller: _website,
                        label: 'Website',
                        keyboardType: TextInputType.url,
                      ),
                      _field(
                        keyName: 'venue-sponsor-field',
                        controller: _sponsor,
                        label: 'Sponsor / hosting organization',
                      ),
                      _sectionLabel(theme, 'Address'),
                      _field(
                        keyName: 'venue-address1-field',
                        controller: _address1,
                        label: 'Address line 1',
                      ),
                      _field(
                        keyName: 'venue-address2-field',
                        controller: _address2,
                        label: 'Address line 2',
                      ),
                      _field(
                        keyName: 'venue-city-field',
                        controller: _city,
                        label: 'City',
                      ),
                      _field(
                        keyName: 'venue-state-field',
                        controller: _stateProv,
                        label: 'State / province',
                      ),
                      _field(
                        keyName: 'venue-country-field',
                        controller: _country,
                        label: 'Country',
                      ),
                      _field(
                        keyName: 'venue-postal-field',
                        controller: _postalCode,
                        label: 'Postal / ZIP code',
                      ),
                      _field(
                        keyName: 'venue-plus4-field',
                        controller: _plus4,
                        label: 'ZIP+4',
                      ),
                      _sectionLabel(theme, 'Schedule'),
                      _field(
                        keyName: 'venue-event-name-field',
                        controller: _eventName,
                        label: 'Event name',
                      ),
                      _field(
                        keyName: 'venue-time-field',
                        controller: _time,
                        label: 'Time',
                      ),
                      _field(
                        keyName: 'venue-schedule-field',
                        controller: _genericSchedule,
                        label: 'Schedule (e.g. “2nd Saturdays”)',
                      ),
                      _field(
                        keyName: 'venue-price-field',
                        controller: _price,
                        label: 'Price',
                      ),
                      _sectionLabel(theme, 'Contacts'),
                      _field(
                        keyName: 'venue-contact1-name-field',
                        controller: _contact1Name,
                        label: 'Contact 1 name',
                      ),
                      _field(
                        keyName: 'venue-contact1-phone-field',
                        controller: _contact1Phone,
                        label: 'Contact 1 phone',
                        keyboardType: TextInputType.phone,
                      ),
                      _field(
                        keyName: 'venue-contact1-email-field',
                        controller: _contact1Email,
                        label: 'Contact 1 email',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _field(
                        keyName: 'venue-contact2-name-field',
                        controller: _contact2Name,
                        label: 'Contact 2 name',
                      ),
                      _field(
                        keyName: 'venue-contact2-phone-field',
                        controller: _contact2Phone,
                        label: 'Contact 2 phone',
                        keyboardType: TextInputType.phone,
                      ),
                      _field(
                        keyName: 'venue-contact2-email-field',
                        controller: _contact2Email,
                        label: 'Contact 2 email',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _sectionLabel(theme, 'Notes'),
                      _field(
                        keyName: 'venue-notes-field',
                        controller: _notes,
                        label: 'Notes',
                        minLines: 2,
                        maxLines: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('venue-editor-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('venue-editor-save'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  Widget _field({
    required String keyName,
    required TextEditingController controller,
    required String label,
    bool autofocus = false,
    int? minLines,
    int? maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(keyName),
        controller: controller,
        autofocus: autofocus,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: maxLines == 1
            ? TextInputAction.next
            : TextInputAction.newline,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: (minLines ?? 1) > 1,
        ),
      ),
    );
  }
}
