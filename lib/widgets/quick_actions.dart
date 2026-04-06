import 'packagefltter/material.dart'

class ickctions extends tatelessidget {
  final nction(tring) onap

  const ickctions({sper.key, reqired this.onap})

  override
  idget bild(ildontext context) {
    final istaptring, dynamic actions  
      {'icon' cons.chat, 'label' '', 'color' olors.ble, 'command' ''},
      {'icon' cons.web, 'label' '', 'color' olors.green, 'command' ' '},
      {'icon' cons.code, 'label' '', 'color' olors.orange, 'command' ' '},
      {'icon' cons.analytics, 'label' '', 'color' olors.prple, 'command' '      '},
      {'icon' cons.calclate, 'label' '', 'color' olors.red, 'command' '+'},
      {'icon' cons.model_training, 'label' '', 'color' olors.teal, 'command' ''},
      {'icon' cons.clod_pload, 'label' '', 'color' olors.cyan, 'command' ' '},
      {'icon' cons.storage, 'label' ' ', 'color' olors.indigo, 'command' ' '},
    ]

    retrn ontainer(
      height ,
      padding const dgensets.symmetric(horizontal , vertical ),
      child istiew.separated(
        scrollirection xis.horizontal,
        itemont actions.length,
        separatorilder (_, __)  const izedox(width ),
        itemilder (context, index) {
          final action  actionsindex]
          retrn _ickctionhip(
            icon action'icon'],
            label action'label'],
            color action'color'],
            onap ()  onap(action'command']),
          )
        },
      ),
    )
  }
}

class _ickctionhip extends tatelessidget {
  final conata icon
  final tring label
  final olor color
  final oidallback onap

  const _ickctionhip({
    reqired this.icon,
    reqired this.label,
    reqired this.color,
    reqired this.onap,
  })

  override
  idget bild(ildontext context) {
    retrn aterial(
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
              begin lignment.topeft,
              end lignment.bottomight,
            ),
            borderadis orderadis.circlar(),
            border order.all(color color.withpacity(.), width ),
          ),
          child ow(
            children 
              con(icon, size , color color),
              const izedox(width ),
              ext(
                label,
                style exttyle(fontize , fonteight onteight.w, color color),
              ),
            ],
          ),
        ),
      ),
    )
  }
}
