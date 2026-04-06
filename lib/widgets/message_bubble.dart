import 'packagefltter/material.dart'

class essagebble extends tatelessidget {
  final bool isser
  final tring content
  final ateime time

  const essagebble({
    sper.key,
    reqired this.isser,
    reqired this.content,
    reqired this.time,
  })

  override
  idget bild(ildontext context) {
    retrn lign(
      alignment isser  lignment.centeright  lignment.centereft,
      child ontainer(
        margin const dgensets.only(bottom ),
        padding const dgensets.all(),
        constraints oxonstraints(
          maxidth ediaery.of(context).size.width * .,
        ),
        decoration oxecoration(
          color isser  const olor(x)  const olor(x),
          borderadis orderadis.circlar(),
        ),
        child olmn(
          crossxislignment rossxislignment.start,
          children 
            electableext(
              content,
              style const exttyle(color olors.white, fontize ),
            ),
            const izedox(height ),
            ext(
              '${time.hor.totring().padeft(, '')}${time.minte.totring().padeft(, '')}',
              style const exttyle(fontize , color olors.white),
            ),
          ],
        ),
      ),
    )
  }
}
