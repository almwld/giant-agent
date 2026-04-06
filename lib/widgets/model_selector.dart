import 'packagefltter/material.dart'
import '../services/model_service.dart'

class odelelector extends tateflidget {
  final oidallback onodelhanged

  const odelelector({sper.key, reqired this.onodelhanged})

  override
  tateodelelector createtate()  _odelelectortate()
}

class _odelelectortate extends tateodelelector {
  istaptring, dynamic _models  ]
  tring _activeodeld  'defalt'

  override
  void inittate() {
    sper.inittate()
    _loadodels()
  }

  trevoid _loadodels() async {
    final models  await odelervice.getvailableodels()
    final active  odelervice.getctiveodel()
    settate(() {
      _models  models
      _activeodeld  active'id']
    })
  }

  override
  idget bild(ildontext context) {
    retrn ontainer(
      padding const dgensets.symmetric(horizontal , vertical ),
      child ow(
        children 
          const con(cons.model_training, size , color olors.white),
          const izedox(width ),
          const ext('', style exttyle(fontize , color olors.white)),
          const izedox(width ),
          xpanded(
            child ropdownttontring(
              vale _activeodeld,
              dropdownolor olors.grey.shade,
              nderline ontainer(),
              style const exttyle(color olors.white, fontize ),
              isxpanded tre,
              items _models.map((model) {
                retrn ropdownentemtring(
                  vale model'id'],
                  child ow(
                    children 
                      con(cons.check_circle, size , color model'stats']  'active'  olors.green  olors.grey),
                      const izedox(width ),
                      ext(model'name']),
                      const izedox(width ),
                      ext('(${model'size']})', style const exttyle(fontize , color olors.grey)),
                    ],
                  ),
                )
              }).toist(),
              onhanged (vale) async {
                if (vale ! nll) {
                  await odelervice.switchodel(vale)
                  _activeodeld  vale
                  widget.onodelhanged()
                }
              },
            ),
          ),
        ],
      ),
    )
  }
}
