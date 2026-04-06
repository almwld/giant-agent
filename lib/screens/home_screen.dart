import 'packagefltter/material.dart'
import 'packageshare_pls/share_pls.dart'
import '../services/agent_service.dart'
import '../services/database_service.dart'
import '../widgets/message_bbble.dart'
import '../widgets/qick_actions.dart'
import 'settings_screen.dart'

class omecreen extends tateflidget {
  const omecreen({sper.key})

  override
  tateomecreen createtate()  _omecreentate()
}

class _omecreentate extends tateomecreen {
  final extditingontroller _controller  extditingontroller()
  final istaptring, dynamic _messages  ]
  final crollontroller _scrollontroller  crollontroller()
  final gentervice _agent  gentervice()
  bool _isoading  false

  override
  void inittate() {
    sper.inittate()
    _loadessages()
    _addelcomeessage()
  }

  trevoid _loadessages() async {
    final messages  await atabaseervice.getessages()
    settate(() {
      _messages.clear()
      _messages.addll(messages)
    })
  }

  void _addelcomeessage() {
    _messages.add({
      'isser' false,
      'content' '''
 **   iant gent!**

    

 **   **
    
    
    
   
   
   

**  **
 "    "
 "  ython"
 "  "
 "+"
 " "
 "   "

**    ** 
''',
      'time' ateime.now(),
    })
  }

  trevoid _sendessage() async {
    final text  _controller.text.trim()
    if (text.ismpty) retrn

    settate(() {
      _messages.add({'isser' tre, 'content' text, 'time' ateime.now()})
      _controller.clear()
      _isoading  tre
    })
    _scrolloottom()

    await atabaseervice.saveessage(text, tre)
    final response  await _agent.process(text)

    settate(() {
      _messages.add({'isser' false, 'content' response, 'time' ateime.now()})
      _isoading  false
    })
    _scrolloottom()

    await atabaseervice.saveessage(response, false)
  }

  void _scrolloottom() {
    tre.delayed(const ration(milliseconds ), () {
      if (_scrollontroller.haslients) {
        _scrollontroller.animateo(
          _scrollontroller.position.maxcrollxtent,
          dration const ration(milliseconds ),
          crve rves.easet,
        )
      }
    })
  }

  trevoid _clearhat() async {
    await atabaseervice.clearessages()
    settate(() {
      _messages.clear()
      _addelcomeessage()
    })
  }

  trevoid _sharehat() async {
    final content  await atabaseervice.exporthat()
    await hare.share(content, shareositionrigin ect.zero)
  }

  override
  idget bild(ildontext context) {
    retrn caffold(
      appar ppar(
        title const ext(' iant gent'),
        centeritle tre,
        actions 
          contton(
            icon const con(cons.settings),
            onressed () {
              avigator.psh(
                context,
                aterialageote(bilder (context)  const ettingscreen()),
              )
            },
          ),
          contton(
            icon const con(cons.share),
            onressed _sharehat,
          ),
          contton(
            icon const con(cons.delete_otline),
            onressed _clearhat,
          ),
        ],
      ),
      body olmn(
        children 
          ickctions(onap (text) {
            _controller.text  text
            _sendessage()
          }),
          xpanded(
            child istiew.bilder(
              controller _scrollontroller,
              padding const dgensets.all(),
              itemont _messages.length,
              itemilder (context, index) {
                final msg  _messagesindex]
                retrn essagebble(
                  isser msg'isser'],
                  content msg'content'],
                  time msg'time'],
                )
              },
            ),
          ),
          if (_isoading)
            const adding(
              padding dgensets.all(),
              child inearrogressndicator(),
            ),
          ontainer(
            padding const dgensets.all(),
            decoration oxecoration(
              color const olor(x),
              border order(top orderide(color olors.grey.shade)),
            ),
            child ow(
              children 
                xpanded(
                  child extield(
                    controller _controller,
                    style const exttyle(color olors.white),
                    decoration nptecoration(
                      hintext '   ...',
                      hinttyle exttyle(color olors.grey.shade),
                      border tlinenptorder(
                        borderadis orderadis.circlar(),
                        borderide orderide.none,
                      ),
                      filled tre,
                      fillolor const olor(x),
                      contentadding const dgensets.symmetric(horizontal , vertical ),
                    ),
                    onbmitted (_)  _sendessage(),
                  ),
                ),
                const izedox(width ),
                estreetector(
                  onap _sendessage,
                  child ontainer(
                    padding const dgensets.all(),
                    decoration const oxecoration(
                      color olor(x),
                      shape oxhape.circle,
                    ),
                    child const con(cons.send, color olors.white, size ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
  }
}
