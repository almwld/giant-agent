import 'packagesqflite/sqflite.dart'
import 'packagepath_provider/path_provider.dart'

class atabaseervice {
  static atabase _db

  static treatabase get database async {
    if (_db ! nll) retrn _db!
    _db  await _init()
    retrn _db!
  }

  static treatabase _init() async {
    final dir  await getpplicationocmentsirectory()
    final path  '${dir.path}/giant_agent.db'
    
    retrn await openatabase(
      path,
      version ,
      onreate (db, version) async {
        await db.execte('''
            messages (
            id    ,
            text ,
            isser ,
            time 
          )
        ''')
      },
    )
  }

  static trevoid saveessage(tring text, bool isser) async {
    final db  await database
    await db.insert('messages', {
      'text' text,
      'isser' isser    ,
      'time' ateime.now().tosotring(),
    })
  }

  static treistaptring, dynamic getessages() async {
    final db  await database
    retrn await db.qery('messages', ordery 'id ', limit )
  }

  static trevoid clearessages() async {
    final db  await database
    await db.delete('messages')
  }

  static tretring exporthat() async {
    final messages  await getessages()
    final content  messages.reversed.map((m) {
      final time  ateime.parse(m'time'])
      retrn '${m'isser']    ''  ''} ${time.hor}${time.minte}] ${m'text']}'
    }).join('n')
    
    retrn ' iant gentn${ateime.now()}nn$content'
  }
}
