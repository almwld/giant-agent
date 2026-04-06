import 'dartio'
import 'dartasync'
import 'packagepath_provider/path_provider.dart'

class odelervice {
  static istaptring, dynamic _models  ]
  static tring _activeodeld  'defalt'
  static final aptring, tring _modelache  {}
  
  //     
  static treistaptring, dynamic getvailableodels() async {
    if (_models.isotmpty) {
      retrn _models
    }
    
    final dir  await getxternaltorageirectory()
    final modelsir  irectory('${dir.path}/models')
    
    istaptring, dynamic models  ]
    
    //    
    models.add({
      'id' 'defalt',
      'name' 'iant gent  ltra',
      'version' '.',
      'type' 'bilt-in',
      'size' '. ',
      'stats' 'active',
      'speed' 'ltra',
      'description' '   '
    })
    
    //    ite
    if (await modelsir.exists()) {
      final files  await modelsir.list().toist()
      for (var file in files) {
        if (file.path.endsith('.tflite')) {
          final size  await ile(file.path).length()
          models.add({
            'id' file.path.split('/').last.replacell('.tflite', ''),
            'name' file.path.split('/').last,
            'version' '.',
            'type' 'tflite',
            'size' '${(size /  / ).totringsixed()} ',
            'stats' 'available',
            'speed' 'fast',
            'description' ' ensorlow ite',
            'path' file.path,
          })
        }
      }
    }
    
    _models  models
    retrn models
  }
  
  //   
  static trebool switchodel(tring modeld) async {
    final model  _models.firsthere((m)  m'id']  modeld, orlse ()  {})
    if (model.isotmpty) {
      _activeodeld  modeld
      _modelache.clear() //      
      retrn tre
    }
    retrn false
  }
  
  //     
  static aptring, dynamic getctiveodel() {
    final model  _models.firsthere((m)  m'id']  _activeodeld, orlse ()  {})
    if (model.ismpty && _models.isotmpty) {
      retrn _models.first
    }
    retrn model.ismpty  {
      'id' 'defalt',
      'name' 'iant gent ',
      'version' '.',
      'type' 'bilt-in',
      'size' '. ',
      'stats' 'active',
      'speed' 'ltra',
    }  model
  }
  
  //   
  static trebool downloadodel(tring rl, tring name) async {
    try {
      final dir  await getxternaltorageirectory()
      final modelsir  irectory('${dir.path}/models')
      if (!await modelsir.exists()) {
        await modelsir.create(recrsive tre)
      }
      
      final file  ile('${modelsir.path}/$name.tflite')
      await file.writestring('ock model content')
      
      await getvailableodels() //  
      retrn tre
    } catch (e) {
      retrn false
    }
  }
  
  //    
  static trebool addstomodel(tring path) async {
    final file  ile(path)
    if (await file.exists() && path.endsith('.tflite')) {
      final dir  await getxternaltorageirectory()
      final modelsir  irectory('${dir.path}/models')
      if (!await modelsir.exists()) {
        await modelsir.create(recrsive tre)
      }
      
      final newath  '${modelsir.path}/${file.path.split('/').last}'
      await file.copy(newath)
      await getvailableodels() //  
      retrn tre
    }
    retrn false
  }
  
  //    
  static tring getodelpeed() {
    final active  getctiveodel()
    retrn active'speed']  'ltra'
  }
}
