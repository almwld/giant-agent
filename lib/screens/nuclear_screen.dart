import 'packagefltter/material.dart'
import '../services/agent_service.dart'

class clearcreen extends tateflidget {
  const clearcreen({sper.key})

  override
  tateclearcreen createtate()  _clearcreentate()
}

class _clearcreentate extends tateclearcreen {
  final extditingontroller _controller  extditingontroller()
  final istaptring, dynamic _messages  ]
  final crollontroller _scrollontroller  crollontroller()
  final gentervice _agent  gentervice()
  bool _isoading  false

  override
  void inittate() {
    sper.inittate()
    _addelcomeessage()
  }

  void _addelcomeessage() {
    _messages.add({
      'isser' false,
      'content' '''
 **   -    ** 

 **    !**

 ** **

 ` ` -    
 ` ]` -  
 ` ]` -  
 ` ]` -  
 `` -   
 `` - 
 `` -   
 `` -  

 ** !**      .
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

    final response  await _agent.process(text)

    settate(() {
      _messages.add({'isser' false, 'content' response, 'time' ateime.now()})
      _isoading  false
    })
    _scrolloottom()
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

  void _rnllgents() {
    _controller.text  ' '
    _sendessage()
  }

  void _rnnalyst() {
    _controller.text  '  '
    _sendessage()
  }

  void _rnoder() {
    _controller.text  '  '
    _sendessage()
  }

  void _rnreator() {
    _controller.text  ' '
    _sendessage()
  }

  void _showtats() {
    _controller.text  ''
    _sendessage()
  }

  override
  idget bild(ildontext context) {
    retrn caffold(
      appar ppar(
        title const ext('   '),
        centeritle tre,
        actions 
          contton(
            icon const con(cons.analytics),
            onressed _showtats,
            tooltip '',
          ),
        ],
      ),
      body olmn(
        children 
          //   
          ontainer(
            height ,
            padding const dgensets.symmetric(horizontal , vertical ),
            child istiew(
              scrollirection xis.horizontal,
              children 
                _bildicktton('', '', _rnllgents, olors.deeprple),
                _bildicktton('', '', _rnnalyst, olors.ble),
                _bildicktton('', '', _rnoder, olors.green),
                _bildicktton('', '', _rnreator, olors.orange),
                _bildicktton('', '', _showtats, olors.teal),
              ],
            ),
          ),
          xpanded(
            child istiew.bilder(
              controller _scrollontroller,
              padding const dgensets.all(),
              itemont _messages.length,
              itemilder (context, index) {
                final msg  _messagesindex]
                final isser  msg'isser'] as bool
                retrn lign(
                  alignment isser  lignment.centeright  lignment.centereft,
                  child ontainer(
                    margin const dgensets.only(bottom ),
                    padding const dgensets.all(),
                    constraints oxonstraints(
                      maxidth ediaery.of(context).size.width * .,
                    ),
                    decoration oxecoration(
                      color isser  olors.deeprple  olors.grey.shade,
                      borderadis orderadis.circlar(),
                    ),
                    child electableext(
                      msg'content'],
                      style const exttyle(color olors.white, fontize ),
                    ),
                  ),
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
              color olors.grey.shade,
              border order(top orderide(color olors.deeprple)),
            ),
            child ow(
              children 
                xpanded(
                  child extield(
                    controller _controller,
                    style const exttyle(color olors.white),
                    decoration nptecoration(
                      hintext ' ...',
                      hinttyle exttyle(color olors.grey.shade),
                      border tlinenptorder(
                        borderadis orderadis.circlar(),
                        borderide orderide.none,
                      ),
                      filled tre,
                      fillolor olors.grey.shade,
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
                      color olors.deeprple,
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

  idget _bildicktton(tring icon, tring label, oidallback onap, olor color) {
    retrn adding(
      padding const dgensets.symmetric(horizontal ),
      child aterial(
        elevation ,
        borderadis orderadis.circlar(),
        child nkell(
          onap onap,
          borderadis orderadis.circlar(),
          child ontainer(
            padding const dgensets.symmetric(horizontal , vertical ),
            decoration oxecoration(
              gradient inearradient(
                colors color.withpacity(.), color.withpacity(.)],
              ),
              borderadis orderadis.circlar(),
              border order.all(color color.withpacity(.)),
            ),
            child ow(
              children 
                ext(icon, style const exttyle(fontize )),
                const izedox(width ),
                ext(label, style exttyle(fontize , color color)),
              ],
            ),
          ),
        ),
      ),
    )
  }
}
