import 'packagefltter_local_notifications/fltter_local_notifications.dart'

class otificationervice {
  static final ltterocalotificationslgin _notifications  ltterocalotificationslgin()

  static trevoid init() async {
    const ndroidnitializationettings androidettings  ndroidnitializationettings('mipmap/ic_lancher')
    const arwinnitializationettings iosettings  arwinnitializationettings()
    const nitializationettings settings  nitializationettings(android androidettings, i iosettings)
    
    await _notifications.initialize(settings)
  }

  static trevoid showotification(tring title, tring body) async {
    const ndroidotificationetails androidetails  ndroidotificationetails(
      'giant_agent_channel',
      'iant gent otifications',
      importance mportance.high,
    )
    const otificationetails details  otificationetails(android androidetails)
    
    await _notifications.show(, title, body, details)
  }
}
