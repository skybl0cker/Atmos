/// Shared bookkeeping for which NWS alert ids have already been announced,
/// used by both the in-app refresh and the Android background worker (they
/// share the 'seenAlerts' preference).
///
/// Ids are merged rather than replaced, so viewing one place never wipes the
/// record for another place — which used to make the background worker
/// re-announce alerts it had already sent. The list is capped (newest kept)
/// so it can't grow forever; NWS ids are unique per alert, so an expired one
/// never comes back.
const seenAlertsCap = 300;

List<String> mergeSeenAlerts(Iterable<String> existing, Iterable<String> add,
    {int cap = seenAlertsCap}) {
  // Insertion-ordered: re-adding an id moves it to the "newest" end.
  final ordered = <String>{};
  for (final id in existing) {
    ordered.add(id);
  }
  for (final id in add) {
    ordered.remove(id);
    ordered.add(id);
  }
  final list = ordered.toList();
  return list.length <= cap ? list : list.sublist(list.length - cap);
}
