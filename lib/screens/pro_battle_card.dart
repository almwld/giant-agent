import 'package:flutter/material.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
class ProBattleCard extends StatelessWidget {
 const ProBattleCard({super.key});
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:ProTheme.bgDark,appBar:const ProAppBar(title:'Battle-card Hub'),body:Container(decoration:const BoxDecoration(gradient:ProTheme.bgGradient),child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:ProTheme.cardGradient,borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.orangeAccent.withOpacity(.3))),child:const Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.insights_outlined,color:Colors.orangeAccent,size:42),SizedBox(height:14),Text('Competitor intelligence is not configured',style:TextStyle(color:ProTheme.textPrimary,fontWeight:FontWeight.bold,fontSize:17),textAlign:TextAlign.center),SizedBox(height:8),Text('No competitor database, win/loss source, pricing feed or comparison provider is connected. Import verified source material to create evidence-based battle cards. No demo metrics are shown.',style:TextStyle(color:ProTheme.textSecondary,height:1.5),textAlign:TextAlign.center)]))))));
}
