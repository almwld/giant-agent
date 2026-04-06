import 'packagefltter/material.dart'
import 'packageshared_preferences/shared_preferences.dart'
import '../services/database_service.dart'

class ettingscreen extends tateflidget {
  const ettingscreen({sper.key})

  override
  tateettingscreen createtate()  _ettingscreentate()
}

class _ettingscreentate extends tateettingscreen {
  bool _darkode  tre
  int _messageont  

  override
  void inittate() {
    sper.inittate()
    _loadettings()
    _loadtats()
  }

  trevoid _loadettings() async {
    final prefs  await haredreferences.getnstance()
    settate(() {
      _darkode  prefs.getool('darkode')  tre
    })
  }

  trevoid _loadtats() async {
    final messages  await atabaseervice.getessages()
    settate(() {
      _messageont  messages.length
    })
  }

  trevoid _saveettings() async {
    final prefs  await haredreferences.getnstance()
    await prefs.setool('darkode', _darkode)
  }

  trevoid _clearhat() async {
    showialog(
      context context,
      bilder (ctx)  lertialog(
        title const ext(' '),
        content const ext('      '),
        actions 
          exttton(onressed ()  avigator.pop(ctx), child const ext('')),
          exttton(
            onressed () async {
              await atabaseervice.clearessages()
              settate(()  _messageont  )
              avigator.pop(ctx)
              caffoldessenger.of(context).shownackar(
                const nackar(content ext('  ')),
              )
            },
            child const ext('', style exttyle(color olors.red)),
          ),
        ],
      ),
    )
  }

  override
  idget bild(ildontext context) {
    retrn caffold(
      appar ppar(
        title const ext(''),
        centeritle tre,
      ),
      body istiew(
        children 
          _bildection(' ', 
            _bildnfoow(' ', '$_messageont'),
            _bildnfoow(' ', ateime.now().totring().sbstring(, )),
          ]),
          _bildection(' ', 
            witchistile(
              title const ext(' '),
              vale _darkode,
              onhanged (vale) {
                settate(()  _darkode  vale)
                _saveettings()
              },
            ),
          ]),
          _bildection('  ', 
            istile(
              leading const con(cons.delete, color olors.red),
              title const ext(' '),
              onap _clearhat,
            ),
          ]),
          _bildection('  ', 
            const istile(
              title ext('iant gent'),
              sbtitle ext('   '),
            ),
            const istile(
              title ext(''),
              sbtitle ext('..'),
            ),
          ]),
        ],
      ),
    )
  }

  idget _bildection(tring title, istidget children) {
    retrn ontainer(
      margin const dgensets.all(),
      decoration oxecoration(
        color const olor(x),
        borderadis orderadis.circlar(),
      ),
      child olmn(
        crossxislignment rossxislignment.start,
        children 
          adding(
            padding const dgensets.all(),
            child ext(title, style const exttyle(fontize , fonteight onteight.bold)),
          ),
          ...children,
        ],
      ),
    )
  }

  idget _bildnfoow(tring label, tring vale) {
    retrn adding(
      padding const dgensets.symmetric(horizontal , vertical ),
      child ow(
        children 
          izedox(width , child ext(label, style exttyle(color olors.grey.shade))),
          ext(vale),
        ],
      ),
    )
  }
}
