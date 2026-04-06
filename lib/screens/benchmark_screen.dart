import 'packagefltter/material.dart'
import '../services/agent_service.dart'

class enchmarkcreen extends tateflidget {
  const enchmarkcreen({sper.key})

  override
  tateenchmarkcreen createtate()  _enchmarkcreentate()
}

class _enchmarkcreentate extends tateenchmarkcreen {
  final gentervice _agent  gentervice()
  bool _isnning  false
  tring _reslts  ''

  trevoid _rnenchmark() async {
    settate(() {
      _isnning  tre
      _reslts  ''
    })
    
    final reslt  await _agent.process('benchmark')
    
    settate(() {
      _reslts  reslt
      _isnning  false
    })
  }

  override
  idget bild(ildontext context) {
    retrn caffold(
      appar ppar(
        title const ext('  '),
        centeritle tre,
        backgrondolor olors.deeprple,
      ),
      body adding(
        padding const dgensets.all(),
        child olmn(
          children 
            levatedtton.icon(
              onressed _isnning  nll  _rnenchmark,
              icon const con(cons.speed),
              label ext(_isnning  ' ...'  ' '),
              style levatedtton.stylerom(
                backgrondolor olors.deeprple,
                minimmize const ize(doble.infinity, ),
              ),
            ),
            const izedox(height ),
            if (_reslts.isotmpty)
              xpanded(
                child inglehildcrolliew(
                  child ontainer(
                    padding const dgensets.all(),
                    decoration oxecoration(
                      color olors.grey.shade,
                      borderadis orderadis.circlar(),
                    ),
                    child ext(
                      _reslts,
                      style const exttyle(fontamily 'monospace', fontize ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    )
  }
}
