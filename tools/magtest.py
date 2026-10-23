import sys, subprocess, os
# gun: class, well, axis, mouth, topinhand (gun frame cm: x fwd, y left, z up); shots to fire first
G={
 'PulseRifle_3D':      ((8.79,0.01,-8.41),(0,0,1),10.8,(-0.84,3.914,9.036)),
 'M240Flamethrower_3D':((22.17,-0.19,-0.22),(0.015,-0.003,1),1.9,(-0.598,3.859,13.705)),
 'Smartgun_3D':        ((6.61,9.03,-5.2),(0.988,-0.099,-0.117),11.7,(8.609,1.777,-5.067)),
}
cls=sys.argv[1]; shots=int(sys.argv[2]); name=sys.argv[3]
well,ax,mouth,tih=G[cls]
R=(0.25,1.3,-0.3)
def world(off):  # off = (fwd,left,up) cm -> world m
    return (R[0]-off[1]/100, R[1]+off[2]/100, R[2]-off[0]/100)
steps=[]
for k,d in enumerate([mouth+10, mouth+6, mouth+3, mouth, mouth*0.6, mouth*0.25, 0.0]):
    top=[well[i]+ax[i]*d for i in range(3)]
    hand=[top[i]-tih[i] for i in range(3)]
    w=world(hand)
    steps.append(f'qz_lhand "{w[0]:.3f} {w[1]:.3f} {w[2]:.3f} 30 0 0"; wait 12; qz_shot runs/{name}_{k}.ppm; wait 3;')
fire='qz_rtrigger 1; wait 4; qz_rtrigger 0; wait 24; '*shots
s=f'wait 50; give {cls}; wait 3; use {cls}; wait 40; rsr_debug 1; qz_hmd "0.1 1.6 0 -35 0 0"; wait 10; {fire}+reload; wait 6; -reload; wait 30; qz_lhand "0.25 1.7 -0.6 30 0 0"; qz_ltrigger 1; wait 10; qz_shot runs/{name}_carry.ppm; wait 3; '+' '.join(steps)+' wait 10; qz_ltrigger 0; wait 30; quit'
print(s)
