package com.leqra.android.render

import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.MotionEvent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.GameSession
import com.leqra.android.Screen
import com.leqra.android.accounts.isolatedAccountContext
import com.leqra.core.MuzzlePresentation
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real transport, native Canvas and touch input; only the encounter setup is a fixture. */
@RunWith(AndroidJUnit4::class)
class MuzzleOnlineDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }
    private fun eventually(message: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime()+20000
        while (SystemClock.elapsedRealtime()<until) {
            if (main(condition)) return
            Thread.sleep(40)
        }
        throw AssertionError(message)
    }
    @Test fun realOnlineGhostMuzzleAndTouchTurning() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Requires the disposable native device server", server != null)
        fun fixture(body: JSONObject): JSONObject {
            val connection = URL(server+"/_fixture/muzzle").openConnection() as HttpURLConnection
            try {
                connection.requestMethod="POST"; connection.doOutput=true
                connection.connectTimeout=10000; connection.readTimeout=10000
                connection.setRequestProperty("Content-Type","application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray()) }
                assertEquals(200,connection.responseCode)
                return JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            } finally { connection.disconnect() }
        }
        for (infinity in listOf(false,true)) {
            val base=isolatedAccountContext()
            val stamp=UUID.randomUUID().toString()
            val context=object:ContextWrapper(base){
                override fun getNoBackupFilesDir():File=base.noBackupFilesDir
                override fun getSharedPreferences(name:String,mode:Int):SharedPreferences=super.getSharedPreferences("muzzle-$stamp-$name",mode)
            }
            val name="MuzzleA"+stamp.take(6)
            lateinit var session:GameSession
            lateinit var view:NativeArenaView
            val scenario=ActivityScenario.launch(RenderBenchmarkActivity::class.java)
            try {
                scenario.onActivity { activity ->
                    view=activity.arena; session=GameSession(context)
                    session.setServer(server!!);session.callsign=name;session.botCount=1
                    session.togglePublic(false);session.selectMode(if(infinity)"infinity" else "elimination")
                    session.changeRules(session.rules.copy(infinityRandomBots=false))
                    session.present={snapshot,maze,id,id2,online->view.submit(snapshot,id,maze,id2,online)}
                    view.onInput={session.input=view.input.copy()}
                    view.onFrame={nanos->session.input=view.input.copy();session.frame(nanos)}
                    session.foreground();session.share()
                }
                eventually("Room did not connect"){session.network.connected&&session.room!=null}
                val code=main{session.room!!.getString("code")}
                main{session.play()}
                eventually("Online arena did not start"){session.screen==Screen.PLAYING&&session.online&&session.snapshot.tanks.isNotEmpty()&&session.maze!=null}
                for(landscape in listOf(false,true)){
                    scenario.onActivity{it.requestedOrientation=if(landscape)ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT}
                    eventually("Rotation did not finish"){(view.width>view.height)==landscape&&view.width>0}
                    val cases=listOf(Triple("",false,22.0),Triple("",true,1.0),Triple("",true,22.0))+
                        listOf("","rapid","scatter","homing","grenade","laser","cannon").map{Triple(it,true,8.0)}
                    fun request(read:Boolean=false,weapon:String="",ghost:Boolean=false,gap:Double=22.0)=JSONObject()
                        .put("name",name).put("code",code).put("infinity",infinity).put("read",read)
                        .put("weapon",weapon).put("ghost",ghost).put("gap",gap)
                    fun coordinate(field:String):Float=main{
                        NativeArenaView::class.java.getDeclaredField(field).apply{isAccessible=true}.getFloat(view)*view.resources.displayMetrics.density
                    }
                    fun touch(action:Int,x:Float,y:Float,began:Long){main{
                        val event=MotionEvent.obtain(began,SystemClock.uptimeMillis(),action,x,y,0)
                        view.dispatchTouchEvent(event);event.recycle()
                    }}
                    for((weapon,ghost,gap)in cases){
                        val setup=fixture(request(weapon=weapon,ghost=ghost,gap=gap))
                        eventually("Configured pilot was not rendered"){
                            val tank=session.snapshot.tanks.firstOrNull{it.id==session.localID}
                            tank!=null&&kotlin.math.abs(tank.x-setup.getDouble("x"))<1&&(tank.ghostTime>0)==ghost
                        }
                        main{
                            val tank=session.snapshot.tanks.first{it.id==session.localID}
                            assertTrue("Visible barrel crosses cover",30-MuzzlePresentation.retraction(tank,session.maze)<=gap+.1)
                            assertTrue(view.renderedFrames>0)
                        }
                        val x=coordinate("fireX")
                        val y=coordinate("fireY")
                        val began=SystemClock.uptimeMillis()
                        touch(MotionEvent.ACTION_DOWN,x,y,began);Thread.sleep(140);touch(MotionEvent.ACTION_UP,x,y,began)
                        var result=fixture(request(read=true))
                        for(attempt in 0..30){if(result.getInt("shots")>0)break;Thread.sleep(40);result=fixture(request(read=true))}
                        assertTrue("Fire never reached Go",result.getInt("shots")>0)
                        if(weapon!="cannon"){
                            val bullets=result.optJSONArray("bullets")
                            if(bullets!=null)for(i in 0 until bullets.length()){
                                assertTrue("Bullet crossed cover",bullets.getJSONObject(i).getDouble("x")<=setup.getDouble("wallX")+.1)
                                assertTrue(bullets.getJSONObject(i).optInt("bounces")>0)
                            }
                        }
                        android.util.Log.i("MuzzleDevice","PASS infinity=$infinity landscape=$landscape weapon=$weapon ghost=$ghost gap=$gap")
                        if(weapon==""&&gap==1.0||weapon=="cannon"){
                            val file=File(instrumentation.targetContext.getExternalFilesDir(null),"muzzle-$infinity-$landscape-${weapon.ifEmpty{"ghost"}}.png")
                            instrumentation.uiAutomation.takeScreenshot()?.let{image->file.outputStream().use{image.compress(Bitmap.CompressFormat.PNG,100,it)};image.recycle()}
                        }
                    }
                    fixture(request())
                    Thread.sleep(250)
                    val x=coordinate("stickX")
                    val y=coordinate("stickY")
                    val began=SystemClock.uptimeMillis()
                    touch(MotionEvent.ACTION_DOWN,x,y,began);touch(MotionEvent.ACTION_MOVE,x,y-100,began)
                    Thread.sleep(500);touch(MotionEvent.ACTION_UP,x,y-100,began)
                    val turned=fixture(request(read=true))
                    assertTrue("Touch turn never reached Go",kotlin.math.abs(turned.getDouble("angle"))>.5)
                    assertTrue(turned.getJSONObject("input").getBoolean("touchAim"))
                }
            } finally {
                main{session.leave();session.release()};scenario.close();context.noBackupFilesDir.deleteRecursively()
            }
        }
    }
}
