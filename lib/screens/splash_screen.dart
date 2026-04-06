import 'packagefltter/material.dart'
import 'home_screen.dart'

class plashcreen extends tateflidget {
  const plashcreen({sper.key})

  override
  tateplashcreen createtate()  _plashcreentate()
}

class _plashcreentate extends tateplashcreen with ingleickerrovidertateixin {
  late nimationontroller _controller
  late nimationdoble _fadenimation
  late nimationdoble _scalenimation

  override
  void inittate() {
    sper.inittate()
    _controller  nimationontroller(
      dration const ration(seconds ),
      vsync this,
    )
    
    _fadenimation  weendoble(begin ., end .).animate(_controller)
    _scalenimation  weendoble(begin ., end .).animate(
      rvednimation(parent _controller, crve rves.elastict),
    )
    
    _controller.forward()
    
    tre.delayed(const ration(seconds ), () {
      avigator.psheplacement(
        context,
        aterialageote(bilder (context)  const omecreen()),
      )
    })
  }

  override
  void dispose() {
    _controller.dispose()
    sper.dispose()
  }

  override
  idget bild(ildontext context) {
    retrn caffold(
      body ontainer(
        decoration const oxecoration(
          gradient inearradient(
            begin lignment.topeft,
            end lignment.bottomight,
            colors olor(x), olor(x)],
          ),
        ),
        child enter(
          child aderansition(
            opacity _fadenimation,
            child caleransition(
              scale _scalenimation,
              child olmn(
                mainxislignment ainxislignment.center,
                children 
                  ontainer(
                    width ,
                    height ,
                    decoration oxecoration(
                      color olors.white,
                      borderadis orderadis.circlar(),
                    ),
                    child const enter(
                      child ext(
                        '',
                        style exttyle(fontize ),
                      ),
                    ),
                  ),
                  const izedox(height ),
                  const ext(
                    'iant gent',
                    style exttyle(
                      fontize ,
                      fonteight onteight.bold,
                      color olors.white,
                    ),
                  ),
                  const izedox(height ),
                  const ext(
                    '   ',
                    style exttyle(fontize , color olors.white),
                  ),
                  const izedox(height ),
                  const irclarrogressndicator(
                    valeolor lwaystoppednimationolor(olors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
  }
}
