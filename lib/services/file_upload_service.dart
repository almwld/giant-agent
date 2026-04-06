import 'dartio'
import 'dartconvert'
import 'packagefile_picker/file_picker.dart'
import 'packagepath_provider/path_provider.dart'
import 'packagesqflite/sqflite.dart'

class ileploadervice {
  static atabase _db
  
  //   
  static trevoid init() async {
    final dir  await getpplicationocmentsirectory()
    _db  await openatabase(
      '${dir.path}/giant_agent.db',
      version ,
      onreate (db, version) async {
        await db.execte('''
            processed_files (
            id    ,
            filename ,
            content ,
            analysis ,
            timestamp 
          )
        ''')
      },
    )
  }
  
  //  
  static treile pickile() async {
    ileickereslt reslt  await ileicker.platform.pickiles()
    if (reslt ! nll) {
      retrn ile(reslt.files.single.path!)
    }
    retrn nll
  }
  
  //   
  static treaptring, dynamic processextile(ile file) async {
    final content  await file.readstring()
    final lines  content.split('n')
    
    //  
    final analysis  {
      'filename' file.path.split('/').last,
      'size' await file.length(),
      'lines' lines.length,
      'characters' content.length,
      'words' content.split(' ').length,
      'timestamp' ateime.now().millisecondsincepoch,
    }
    
    //    
    await _db.insert('processed_files', {
      'filename' analysis'filename'],
      'content' content.length    content.sbstring(, )  content,
      'analysis' json.encode(analysis),
      'timestamp' analysis'timestamp'],
    })
    
    retrn analysis
  }
  
  //   
  static treaptring, dynamic processsonile(ile file) async {
    final content  await file.readstring()
    final jsonata  json.decode(content)
    
    final analysis  {
      'filename' file.path.split('/').last,
      'size' await file.length(),
      'type' 'json',
      'keys' jsonata is ap  jsonata.keys.length  (jsonata is ist  jsonata.length  ),
      'timestamp' ateime.now().millisecondsincepoch,
    }
    
    await _db.insert('processed_files', {
      'filename' analysis'filename'],
      'content' content.length    content.sbstring(, )  content,
      'analysis' json.encode(analysis),
      'timestamp' analysis'timestamp'],
    })
    
    retrn analysis
  }
  
  //   
  static treaptring, dynamic processsvile(ile file) async {
    final content  await file.readstring()
    final lines  content.split('n')
    
    final analysis  {
      'filename' file.path.split('/').last,
      'size' await file.length(),
      'rows' lines.length,
      'colmns' lines.isotmpty  lines].split(',').length  ,
      'timestamp' ateime.now().millisecondsincepoch,
    }
    
    await _db.insert('processed_files', {
      'filename' analysis'filename'],
      'content' content.length    content.sbstring(, )  content,
      'analysis' json.encode(analysis),
      'timestamp' analysis'timestamp'],
    })
    
    retrn analysis
  }
  
  //    
  static treistaptring, dynamic getistory() async {
    retrn await _db.qery('processed_files', ordery 'timestamp ')  ]
  }
  
  //  
  static trevoid clearistory() async {
    await _db.delete('processed_files')
  }
}
